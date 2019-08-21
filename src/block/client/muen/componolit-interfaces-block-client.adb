
with Ada.Unchecked_Conversion;
with System;
with Interfaces;
with Componolit.Interfaces.Muen;
with Componolit.Interfaces.Muen_Block;
with Componolit.Interfaces.Muen_Registry;
with Musinfo;
with Musinfo.Instance;

package body Componolit.Interfaces.Block.Client with
   SPARK_Mode
is
   use type Musinfo.Memregion_Type;
   package CIM renames Componolit.Interfaces.Muen;
   package Blk renames Componolit.Interfaces.Muen_Block;
   package Reg renames Componolit.Interfaces.Muen_Registry;

   subtype Block_Buffer is Buffer (1 .. 4096);
   function Convert_Buffer is new Ada.Unchecked_Conversion (Blk.Raw_Data_Type, Block_Buffer);
   function Convert_Buffer is new Ada.Unchecked_Conversion (Block_Buffer, Blk.Raw_Data_Type);

   procedure Update_Response_Cache (C : in out Client_Session) with
      Pre  => Initialized (C),
      Post => Initialized (C)
              and Writable (C)'Old    = Writable (C)
              and Block_Count (C)'Old = Block_Count (C)
              and Block_Size (C)'Old  = Block_Size (C);

   procedure Allocate_Request (C : in out Client_Session;
                               R : in out Client_Request;
                               K :        Request_Kind;
                               S :        Id;
                               L :        Count;
                               I :        Request_Id;
                               E :    out Result)
   is
      use type Componolit.Interfaces.Internal.Block.Request_Status;
      use type Standard.Interfaces.Unsigned_32;
      Ev_Type : Blk.Event_Type;
   begin
      if L /= 1 then
         E := Unsupported;
         return;
      end if;
      if S > Id (Blk.Sector'Last) then
         E := Unsupported;
         return;
      end if;
      case K is
         when Read   => Ev_Type := Blk.Read;
         when Write  => Ev_Type := Blk.Write;
         when others =>
            E := Unsupported;
            return;
      end case;
      E                    := Success;
      R.Status             := Componolit.Interfaces.Internal.Block.Allocated;
      R.Session            := C.Tag;
      R.Event.Header.Kind  := Ev_Type;
      R.Event.Header.Id    := Blk.Sector (S);
      R.Event.Header.Priv  := Request_Id'Pos (I);
      R.Event.Header.Error := 0;
      R.Event.Header.Valid := True;
      pragma Assert (Request_Id'Pos (I) <= Request_Id'Pos (Request_Id'Last));
      pragma Assert (Request_Id'Pos (I) = R.Event.Header.Priv);
      pragma Assert (R.Event.Header.Priv <= Request_Id'Pos (Request_Id'Last));
   end Allocate_Request;

   procedure Update_Response_Cache (C : in out Client_Session)
   is
      use type Blk.Client_Response_Channel.Result_Type;
      Res : Blk.Client_Response_Channel.Result_Type;
   begin
      for I in C.Responses'Range loop
         if not C.Responses (I).Header.Valid then
            Blk.Client_Response_Channel.Read (C.Response_Memory,
                                              C.Response_Reader,
                                              C.Responses (I),
                                              Res);
            exit when Res /= Blk.Client_Response_Channel.Success;
         end if;
      end loop;
   end Update_Response_Cache;

   procedure Update_Request (C : in out Client_Session;
                             R : in out Client_Request)
   is
      use type Blk.Event_Type;
      use type Standard.Interfaces.Unsigned_32;
   begin
      Update_Response_Cache (C);
      for I in C.Responses'Range loop
         pragma Loop_Invariant (Initialized (C));
         pragma Loop_Invariant (Status (R) = Pending);
         if
            C.Responses (I).Header.Valid
            and then C.Responses (I).Header.Priv = R.Event.Header.Priv
         then
            if C.Responses (I).Header.Error = 0 then
               R.Status := Componolit.Interfaces.Internal.Block.Ok;
               if R.Event.Header.Kind = Blk.Read then
                  R.Event.Data := C.Responses (I).Data;
               end if;
            else
               R.Status := Componolit.Interfaces.Internal.Block.Error;
            end if;
            C.Responses (I).Header.Valid := False;
            return;
         end if;
      end loop;
   end Update_Request;

   procedure Set_Null (C : in out Client_Session) with
      Post => not Initialized (C);

   procedure Set_Null (C : in out Client_Session)
   is
      use type CIM.Session_Index;
   begin
      C.Name            := Blk.Null_Name;
      C.Count           := 0;
      C.Request_Memory  := Musinfo.Null_Memregion;
      if C.Registry_Index /= CIM.Invalid_Index then
         Reg.Registry (C.Registry_Index) := Reg.Session_Entry'(Kind => CIM.None);
         C.Registry_Index                := CIM.Invalid_Index;
      end if;
      C.Responses := (others => Blk.Null_Event);
   end Set_Null;

   function Event_Address return System.Address;

   function Event_Address return System.Address with
      SPARK_Mode => Off
   is
   begin
      return Event'Address;
   end Event_Address;

   procedure Initialize (C           : in out Client_Session;
                         Cap         :        Componolit.Interfaces.Types.Capability;
                         Path        :        String;
                         Tag         :        Session_Id;
                         Buffer_Size :        Byte_Length := 0)
   is
      use type CIM.Async_Session_Type;
      use type CIM.Session_Index;
      use type Blk.Sector;
      use type Blk.Count;
      use type Blk.Event_Type;
      use type Blk.Client_Response_Channel.Result_Type;
      use type Standard.Interfaces.Unsigned_64;
      pragma Unreferenced (Cap);
      pragma Unreferenced (Buffer_Size);
      Name       : Blk.Session_Name := Blk.Null_Name;
      Req_Name   : Musinfo.Name_Type;
      Res_Name   : Musinfo.Name_Type;
      Req_Mem    : Musinfo.Memregion_Type;
      Res_Mem    : Musinfo.Memregion_Type;
      Index      : CIM.Session_Index := CIM.Invalid_Index;
      Size_Event : Blk.Event := (Header => (Kind  => Blk.Command,
                                            Error => 0,
                                            Id    => Blk.Size,
                                            Valid => True,
                                            Priv  => 0),
                                 Data  => (others => 0));
      Reader     : Blk.Client_Response_Channel.Reader_Type := Blk.Client_Response_Channel.Null_Reader;
      Res        : Blk.Client_Response_Channel.Result_Type;
   begin
      if not Musinfo.Instance.Is_Valid then
         return;
      end if;
      if Path'Length <= Blk.Session_Name'Length then
         for I in Reg.Registry'Range loop
            if Reg.Registry (I).Kind = CIM.None then
               Index := I;
               exit;
            end if;
         end loop;
         Name (Name'First .. Name'First + Path'Length - 1) := Blk.Session_Name (Path);
         Req_Name := CIM.String_To_Name ("blk:req:" & CIM.Str_Cut (String (Name)));
         Res_Name := CIM.String_To_Name ("blk:rsp:" & CIM.Str_Cut (String (Name)));
         Req_Mem := Musinfo.Instance.Memory_By_Name (Req_Name);
         Res_Mem := Musinfo.Instance.Memory_By_Name (Res_Name);
         if
            Index /= CIM.Invalid_Index
            and then Req_Mem /= Musinfo.Null_Memregion
            and then Res_Mem /= Musinfo.Null_Memregion
            and then Req_Mem.Size = Blk.Channel_Size
            and then Res_Mem.Size = Blk.Channel_Size
            and then Req_Mem.Flags.Channel
            and then Res_Mem.Flags.Channel
            and then Req_Mem.Flags.Writable
            and then not Res_Mem.Flags.Writable
         then
            Blk.Client_Request_Channel.Activate (Req_Mem, Blk.Client_Request_Channel.Channel.Header_Field_Type
                                                      (Musinfo.Instance.TSC_Schedule_Start));
            Blk.Client_Request_Channel.Write (Req_Mem, Size_Event);
            loop
               Blk.Client_Response_Channel.Read (Res_Mem, Reader, Size_Event, Res);
               exit when Res = Blk.Client_Response_Channel.Epoch_Changed
                         or Res = Blk.Client_Response_Channel.Success;
            end loop;
            if
               Size_Event.Header.Kind = Blk.Command and Size_Event.Header.Id = Blk.Size
               and (Res = Blk.Client_Response_Channel.Success or Res = Blk.Client_Response_Channel.Epoch_Changed)
            then
               Reg.Registry (Index) := Reg.Session_Entry'(Kind               => CIM.Block_Client,
                                                          Block_Client_Event => Event_Address);
               C.Registry_Index     := Index;
               C.Name               := Name;
               C.Request_Memory     := Req_Mem;
               C.Response_Memory    := Res_Mem;
               C.Response_Reader    := Reader;
               C.Count              := Blk.Get_Size_Command_Data (Size_Event.Data).Value / 8;
               C.Responses          := (others => Blk.Null_Event);
               C.Tag                := Standard.Interfaces.Unsigned_32'Val
                                          (Session_Id'Pos (Tag) - Session_Id'Pos (Session_Id'First));
            end if;
         end if;
      end if;
   end Initialize;

   procedure Finalize (C : in out Client_Session)
   is
   begin
      Blk.Client_Request_Channel.Deactivate (C.Request_Memory);
      Set_Null (C);
   end Finalize;

   Enqueue_Buffer : Block_Buffer;

   procedure Enqueue (C : in out Client_Session;
                      R : in out Client_Request)
   is
      use type Blk.Event_Type;
   begin
      if C.Queued >= Blk.Element_Count then
         return;
      end if;
      Enqueue_Buffer := (others => Byte'First);
      if R.Event.Header.Kind = Blk.Write then
         Write (C,
                Request_Id'Val (R.Event.Header.Priv),
                Enqueue_Buffer);
         R.Event.Data := Convert_Buffer (Enqueue_Buffer);
      end if;
      Blk.Client_Request_Channel.Write (C.Request_Memory, R.Event);
      R.Status := Componolit.Interfaces.Internal.Block.Pending;
      C.Queued := C.Queued + 1;
   end Enqueue;

   procedure Submit (C : in out Client_Session)
   is
   begin
      C.Queued := 0;
   end Submit;

   pragma Warnings (Off, "mode could be ""in"" instead of ""in out""");
   procedure Read (C : in out Client_Session;
                   R :        Client_Request)
   is
   begin
      Read (C,
            Request_Id'Val (R.Event.Header.Priv),
            Convert_Buffer (R.Event.Data));
   end Read;
   pragma Warnings (On, "mode could be ""in"" instead of ""in out""");

   procedure Release (C : in out Client_Session;
                      R : in out Client_Request)
   is
      use type Standard.Interfaces.Unsigned_32;
   begin
      for I in C.Responses'Range loop
         if
            C.Responses (I).Header.Valid
            and then R.Event.Header.Priv = C.Responses (I).Header.Priv
         then
            C.Responses (I).Header.Valid := False;
            exit;
         end if;
      end loop;
      R.Status       := Componolit.Interfaces.Internal.Block.Raw;
      R.Event.Header := Blk.Null_Event_Header;
   end Release;

   procedure Lemma_Read (C      : in out Client_Session;
                         Req    :        Request_Id;
                         Data   :        Buffer)
   is
   begin
      Read (C, Req, Data);
   end Lemma_Read;

   procedure Lemma_Write (C      : in out Client_Session;
                          Req    :        Request_Id;
                          Data   :    out Buffer)
   is
   begin
      Write (C, Req, Data);
   end Lemma_Write;

end Componolit.Interfaces.Block.Client;
