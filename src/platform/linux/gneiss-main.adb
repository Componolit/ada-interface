
with Ada.Unchecked_Conversion;
with Gneiss_Epoll;
with Gneiss.Linker;
with Gneiss_Internal.Message;
--  with Gneiss.Protocoll;
with Gneiss.Syscall;
with System;
with Componolit.Runtime.Debug;
with RFLX.Session;
with RFLX.Session.Packet;

package body Gneiss.Main with
   SPARK_Mode
is
   use type Gneiss_Epoll.Epoll_Fd;
   use type System.Address;

   type Service_Registry is array (RFLX.Session.Kind_Type'Range) of System.Address;
   type Initializer is record
      Func : System.Address := System.Null_Address;
      Cap  : System.Address := System.Null_Address;
   end record;
   type Initializer_Registry is array (Positive range <>) of Initializer;
   type Initializer_Service_Registry is array (RFLX.Session.Kind_Type'Range) of Initializer_Registry (1 .. 10);

   function Create_Cap (Fd : Integer) return Capability;
   procedure Set_Status (S : Integer);
   procedure Event_Handler;
   procedure Call_Event (Fp : System.Address) with
      Pre => Fp /= System.Null_Address;
   generic
      type Session_Type is limited private;
   procedure Call_Initializer (Cap      : System.Address;
                               Fp       : System.Address;
                               Label    : String;
                               Succ     : Boolean;
                               Filedesc : Integer);

   procedure Register_Service (Kind    :     RFLX.Session.Kind_Type;
                               Fp      :     System.Address;
                               Succ    : out Boolean);
   procedure Register_Initializer (Kind    :     RFLX.Session.Kind_Type;
                                   Fp      :     System.Address;
                                   Cap     :     System.Address;
                                   Succ    : out Boolean);

   procedure Construct (Symbol : System.Address;
                        Cap    : Capability);
   procedure Destruct (Symbol : System.Address);
   procedure Broker_Event;
   function Broker_Event_Address return System.Address;
   procedure Handle_Answer (Context : in out RFLX.Session.Packet.Context;
                            Fd      :        Integer;
                            Label   :        String);
   procedure Load_Message (Context    : in out RFLX.Session.Packet.Context;
                           Label      :    out String;
                           Last_Label :    out Natural;
                           Name       :    out String;
                           Last_Name  :    out Natural);

   Running : constant Integer := -1;
   Success : constant Integer := 0;
   Failure : constant Integer := 1;

   Component_Status : Integer                      := Running;
   Epoll_Fd         : Gneiss_Epoll.Epoll_Fd        := -1;
   Services         : Service_Registry             := (others => System.Null_Address);
   Broker_Fd        : Integer                      := -1;
   Initializers     : Initializer_Service_Registry;

   procedure Call_Initializer (Cap      : System.Address;
                               Fp       : System.Address;
                               Label    : String;
                               Succ     : Boolean;
                               Filedesc : Integer)
   is
      procedure Initialize (Session : in out Session_Type;
                            L       :        String;
                            S       :        Boolean;
                            Fd      :        Integer) with
         Import,
         Address => Fp;
      Session : Session_Type with
         Import,
         Address => Cap;
   begin
      Initialize (Session, Label, Succ, Filedesc);
   end Call_Initializer;

   procedure Message_Initializer is new Call_Initializer (Gneiss_Internal.Message.Client_Session);

   procedure Call_Event (Fp : System.Address)
   is
      procedure Event with
         Import,
         Address => Fp;
   begin
      Event;
   end Call_Event;

   procedure Register_Service (Kind    :     RFLX.Session.Kind_Type;
                               Fp      :     System.Address;
                               Succ    : out Boolean)
   is
   begin
      if
         Fp = System.Null_Address
         or else Services (Kind) /= System.Null_Address
      then
         Succ := False;
      else
         Services (Kind) := Fp;
         Succ := True;
      end if;
   end Register_Service;

   procedure Register_Initializer (Kind :     RFLX.Session.Kind_Type;
                                   Fp   :     System.Address;
                                   Cap  :     System.Address;
                                   Succ : out Boolean)
   is
   begin
      Succ := False;
      if Fp = System.Null_Address or else Cap = System.Null_Address then
         return;
      end if;
      for I in Initializers (Kind)'Range loop
         if Initializers (Kind)(I).Func = System.Null_Address then
            Initializers (Kind)(I) := Initializer'(Func => Fp,
                                                   Cap  => Cap);
            Succ := True;
            return;
         end if;
      end loop;
   end Register_Initializer;

   procedure Run (Name       :     String;
                  Fd         :     Integer;
                  Status     : out Integer)
   is
      use type Gneiss.Linker.Dl_Handle;
      Handle        : Gneiss.Linker.Dl_Handle;
      Construct_Sym : System.Address;
      Destruct_Sym  : System.Address;
   begin
      Broker_Fd := Fd;
      Componolit.Runtime.Debug.Log_Debug ("Main: " & Name);
      Gneiss.Linker.Open (Name, Handle);
      if Handle = Gneiss.Linker.Invalid_Handle then
         Componolit.Runtime.Debug.Log_Error ("Linker handle failed");
         Status := 1;
         return;
      end if;
      Construct_Sym := Gneiss.Linker.Symbol (Handle, "component__construct");
      Destruct_Sym  := Gneiss.Linker.Symbol (Handle, "component__destruct");
      if
         Construct_Sym = System.Null_Address
         or else Destruct_Sym = System.Null_Address
      then
         Componolit.Runtime.Debug.Log_Error ("Linker symbols failed");
         Status := 1;
         return;
      end if;
      Gneiss_Epoll.Create (Epoll_Fd);
      if Epoll_Fd < 0 then
         Componolit.Runtime.Debug.Log_Error ("Epoll creation failed");
         Status := 1;
         return;
      end if;
      Gneiss_Epoll.Add (Epoll_Fd, Broker_Fd, Broker_Event_Address, Status);
      if Status /= 0 then
         Componolit.Runtime.Debug.Log_Error ("Failed to add epoll fd");
         Status := 1;
         return;
      end if;
      Construct (Construct_Sym, Create_Cap (Fd));
      while Component_Status = Running loop
         Event_Handler;
      end loop;
      Destruct (Destruct_Sym);
      Status := Component_Status;
   end Run;

   procedure Event_Handler
   is
      Event_Ptr : System.Address;
      Event     : Gneiss_Epoll.Event;
   begin
      Gneiss_Epoll.Wait (Epoll_Fd, Event, Event_Ptr);
      if Event.Epoll_Hup or else Event.Epoll_Rdhup then
         Componolit.Runtime.Debug.Log_Error ("Socket closed unexpectedly, shutting down");
         raise Program_Error;
      end if;
      if Event.Epoll_In then
         Componolit.Runtime.Debug.Log_Debug ("Received event");
         if Event_Ptr /= System.Null_Address then
            Call_Event (Event_Ptr);
         end if;
      end if;
   end Event_Handler;

   type Bytes_Ptr is access all RFLX.Types.Bytes;
   function Convert is new Ada.Unchecked_Conversion (Bytes_Ptr, RFLX.Types.Bytes_Ptr);
   Read_Buffer : aliased RFLX.Types.Bytes := (1 .. 512 => 0);

   Read_Name  : String (1 .. 255);
   Read_Label : String (1 .. 255);

   procedure Broker_Event
   is
      Truncated  : Boolean;
      Context    : RFLX.Session.Packet.Context;
      Buffer_Ptr : RFLX.Types.Bytes_Ptr := Convert (Read_Buffer'Access);
      Last       : RFLX.Types.Index;
      Fd         : Integer;
      Name_Last  : Natural;
      Label_Last : Natural;
   begin
      Componolit.Runtime.Debug.Log_Debug ("Broker_Event");
      Peek_Message (Broker_Fd, Read_Buffer, Last, Truncated, Fd);
      Gneiss.Syscall.Drop_Message (Broker_Fd);
      if Truncated then
         return;
      end if;
      RFLX.Session.Packet.Initialize (Context, Buffer_Ptr,
                                      RFLX.Types.First_Bit_Index (Read_Buffer'First),
                                      RFLX.Types.Last_Bit_Index (Last));
      RFLX.Session.Packet.Verify_Message (Context);
      if
         not RFLX.Session.Packet.Valid (Context, RFLX.Session.Packet.F_Action)
         or else not RFLX.Session.Packet.Valid (Context, RFLX.Session.Packet.F_Kind)
         or else not RFLX.Session.Packet.Valid (Context, RFLX.Session.Packet.F_Name_Length)
         or else not RFLX.Session.Packet.Valid (Context, RFLX.Session.Packet.F_Payload_Length)
         or else not RFLX.Session.Packet.Present (Context, RFLX.Session.Packet.F_Payload)
      then
         Componolit.Runtime.Debug.Log_Warning ("Invalid message, dropping");
         return;
      end if;
      Load_Message (Context, Read_Label, Label_Last, Read_Name, Name_Last);
      case RFLX.Session.Packet.Get_Action (Context) is
         when RFLX.Session.Request =>
            Componolit.Runtime.Debug.Log_Debug ("Request");
         when RFLX.Session.Confirm =>
            Componolit.Runtime.Debug.Log_Debug ("Confirm");
            Handle_Answer (Context, Fd, Read_Label (Read_Label'First .. Label_Last));
         when RFLX.Session.Reject =>
            Componolit.Runtime.Debug.Log_Debug ("Reject");
            Handle_Answer (Context, Fd, Read_Label (Read_Label'First .. Label_Last));
      end case;
   end Broker_Event;

   procedure Handle_Answer (Context : in out RFLX.Session.Packet.Context;
                            Fd      :        Integer;
                            Label   :        String)
   is
      Kind : constant RFLX.Session.Kind_Type := RFLX.Session.Packet.Get_Kind (Context);
   begin
      Componolit.Runtime.Debug.Log_Debug ("Handle_Answer");
      for I of Initializers (Kind) loop
         if
            I.Func /= System.Null_Address
            and then I.Cap /= System.Null_Address
         then
            Componolit.Runtime.Debug.Log_Debug ("Initialize with Answer " & Label);
            case Kind is
               when RFLX.Session.Message =>
                  Message_Initializer (I.Cap, I.Func, Label, Fd >= 0, Fd);
            end case;
            I.Func := System.Null_Address;
            I.Cap  := System.Null_Address;
         end if;
      end loop;
   end Handle_Answer;

   function Broker_Event_Address return System.Address with
      SPARK_Mode => Off
   is
   begin
      return Broker_Event'Address;
   end Broker_Event_Address;

   function Create_Cap (Fd : Integer) return Capability with
      SPARK_Mode => Off
   is
   begin
      return Capability'(Broker_Fd            => Fd,
                         Set_Status           => Set_Status'Address,
                         Register_Service     => Register_Service'Address,
                         Register_Initializer => Register_Initializer'Address,
                         Epoll_Fd             => Epoll_Fd);
   end Create_Cap;

   procedure Load_Message (Context    : in out RFLX.Session.Packet.Context;
                           Label      :    out String;
                           Last_Label :    out Natural;
                           Name       :    out String;
                           Last_Name  :    out Natural)
   is
      procedure Process_Payload (Payload : RFLX.Types.Bytes);
      procedure Get_Payload is new RFLX.Session.Packet.Get_Payload (Process_Payload);
      procedure Process_Payload (Payload : RFLX.Types.Bytes)
      is
         use type RFLX.Types.Length;
         Label_First : constant RFLX.Types.Length :=
            Payload'First + RFLX.Types.Length (RFLX.Session.Packet.Get_Name_Length (Context));
         Index       : RFLX.Types.Length := Payload'First;
      begin
         for I in Name'Range loop
            exit when Index = Label_First;
            Componolit.Runtime.Debug.Log_Debug ("Name: " & Character'Val (Payload (Index)));
            Name (I)  := Character'Val (Payload (Index));
            Index     := Index + 1;
            Last_Name := I;
         end loop;
         for I in Label'Range loop
            Componolit.Runtime.Debug.Log_Debug ("Label: " & Character'Val (Payload (Index)));
            Label (I)  := Character'Val (Payload (Index));
            Last_Label := I;
            exit when Index = Payload'Last;
            Index      := Index + 1;
         end loop;
      end Process_Payload;
   begin
      Last_Name  := 0;
      Last_Label := 0;
      if
         RFLX.Session.Packet.Has_Buffer (Context)
         and then RFLX.Session.Packet.Present (Context, RFLX.Session.Packet.F_Payload)
      then
         Get_Payload (Context);
      end if;
   end Load_Message;

   procedure Set_Status (S : Integer)
   is
   begin
      Component_Status := (if S = 0 then Success else Failure);
   end Set_Status;

   procedure Construct (Symbol : System.Address;
                        Cap    : Capability)
   is
      procedure Component_Construct (C : Capability) with
         Import,
         Address => Symbol;
   begin
      Component_Construct (Cap);
   end Construct;

   procedure Destruct (Symbol : System.Address)
   is
      procedure Component_Destruct with
         Import,
         Address => Symbol;
   begin
      Component_Destruct;
   end Destruct;

   procedure Peek_Message (Socket    :     Integer;
                           Message   : out RFLX.Types.Bytes;
                           Last      : out RFLX.Types.Index;
                           Truncated : out Boolean;
                           Fd        : out Integer) with
      SPARK_Mode => Off
   is
      use type RFLX.Types.Index;
      Trunc     : Integer;
      Length    : Integer;
   begin
      Gneiss.Syscall.Peek_Message (Socket, Message'Address, Message'Length, Fd, Length, Trunc);
      Truncated := Trunc = 1;
      if Length < 1 then
         Last := RFLX.Types.Index'First;
         return;
      end if;
      Last := (Message'First + RFLX.Types.Index (Length)) - 1;
   end Peek_Message;

end Gneiss.Main;
