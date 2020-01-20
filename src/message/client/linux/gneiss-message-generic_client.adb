
with System;
with Gneiss.Protocol;
with Gneiss.Syscall;
with Gneiss_Epoll;
with Gneiss_Platform;
with Gneiss_Internal.Message;

package body Gneiss.Message.Generic_Client with
   SPARK_Mode
is

   function Get_Event_Address (Session : Client_Session) return System.Address;
   type RFLX_String is array (RFLX.Session.Length_Type range <>) of Character;
   package Proto is new Gneiss.Protocol (Character, RFLX_String);

   procedure Session_Event (Session : in out Client_Session);

   procedure Init (Session  : in out Client_Session;
                   Label    :        String;
                   Success  :        Boolean;
                   Filedesc :        Integer);
   function Init_Cap is new Gneiss_Platform.Create_Initializer_Cap (Client_Session, Init);
   function Event_Cap is new Gneiss_Platform.Create_Event_Cap (Client_Session, Session_Event);

   function Get_Event_Address (Session : Client_Session) return System.Address with
      SPARK_Mode => Off
   is
   begin
      return Session.Event_Cap'Address;
   end Get_Event_Address;

   function Create_Request (Label : RFLX_String) return Proto.Message is
      (Proto.Message'(Length      => Label'Length,
                      Action      => RFLX.Session.Request,
                      Kind        => Session_Type,
                      Name_Length => 0,
                      Payload     => Label));

   procedure Session_Event (Session : in out Client_Session)
   is
      pragma Unreferenced (Session);
   begin
      Event;
   end Session_Event;

   procedure Init (Session  : in out Client_Session;
                   Label    :        String;
                   Success  :        Boolean;
                   Filedesc :        Integer)
   is
      S : Integer;
   begin
      if Label /= Session.Label.Value (Session.Label.Value'First .. Session.Label.Last) then
         return;
      end if;
      if Success then
         Gneiss_Epoll.Add (Session.Epoll_Fd, Filedesc, Get_Event_Address (Session), S);
         if S = 0 then
            Session.File_Descriptor := Filedesc;
         end if;
      end if;
      Session.Pending := False;
      Event;
   end Init;

   C_Label : RFLX_String (1 .. 255);
   procedure Initialize (Session : in out Client_Session;
                         Cap     :        Capability;
                         Label   :        String;
                         Idx     :        Session_Index := 0)
   is
      Succ : Boolean;
   begin
      case Status (Session) is
         when Initialized | Pending =>
            return;
         when Uninitialized =>
            if Label'Length > 255 then
               return;
            end if;
            Session.Index      := Gneiss.Session_Index_Option'(Valid => True, Value => Idx);
            Session.Event_Cap  := Event_Cap (Session);
            Session.Label.Last := Session.Label.Value'First + Label'Length - 1;
            Session.Label.Value
               (Session.Label.Value'First
                .. Session.Label.Value'First + Label'Length - 1) := Label;
            for I in C_Label'Range loop
               C_Label (I) := Session.Label.Value (Positive (I));
            end loop;
            Session.Epoll_Fd := Cap.Epoll_Fd;
            Session.Pending  := True;
            Gneiss_Platform.Call (Cap.Register_Initializer,
                                  Init_Cap (Session),
                                  Session_Type, Succ);
            if Succ then
               Proto.Send_Message
                  (Cap.Broker_Fd,
                   Create_Request (C_Label (C_Label'First ..
                                            RFLX.Session.Length_Type (Session.Label.Last))));
            else
               Init (Session, Label, False, -1);
            end if;
      end case;
   end Initialize;

   function Available (Session : Client_Session) return Boolean is
      (Gneiss_Internal.Message.Peek (Session.File_Descriptor) >= Message_Buffer'Length);

   procedure Write (Session : in out Client_Session;
                    Content :        Message_Buffer) with
      SPARK_Mode => Off
   is
   begin
      Gneiss_Internal.Message.Write (Session.File_Descriptor, Content'Address, Content'Length);
   end Write;

   procedure Read (Session : in out Client_Session;
                   Content :    out Message_Buffer) with
      SPARK_Mode => Off
   is
   begin
      Gneiss_Internal.Message.Read (Session.File_Descriptor, Content'Address, Content'Length);
   end Read;

   procedure Finalize (Session : in out Client_Session)
   is
      Ignore_Success : Integer;
   begin
      Gneiss_Epoll.Remove (Session.Epoll_Fd, Session.File_Descriptor, Ignore_Success);
      Gneiss.Syscall.Close (Session.File_Descriptor);
      Session.Label.Last := 0;
      Session.Index      := Gneiss.Session_Index_Option'(Valid => False);
   end Finalize;

end Gneiss.Message.Generic_Client;
