
with System;
with Cxx;
with Cxx.Block.Client;
with Cxx.Block.Dispatcher;
with Cxx.Block.Server;

package Componolit.Interfaces.Internal.Block is

   type Private_Data is new Cxx.Genode_Uint8_T_Array (1 .. 16);
   Null_Data : Private_Data := (others => 0);

   type Request_Status is (Raw, Allocated, Pending, Ok, Error);

   type Client_Session is limited record
      Instance : Cxx.Block.Client.Class;
   end record;
   type Dispatcher_Session is limited record
      Instance : Cxx.Block.Dispatcher.Class;
   end record;
   type Server_Session is limited record
      Instance : Cxx.Block.Server.Class;
   end record;

   type Client_Instance is record
      Device   : System.Address;
      Callback : System.Address;
      Rw       : System.Address;
      Env      : System.Address;
   end record;
   type Dispatcher_Instance is record
      Root    : System.Address;
      Handler : System.Address;
   end record;
   type Server_Instance is record
      Session     : System.Address;
      Callback    : System.Address;
      Block_Count : System.Address;
      Block_Size  : System.Address;
      Writable    : System.Address;
   end record;

   type Client_Request is limited record
      Packet   : Cxx.Block.Client.Packet_Descriptor;
      Status   : Request_Status;
      Instance : Client_Instance;
   end record;

   type Server_Request is limited record
      Request  : Cxx.Block.Server.Request;
      Status   : Request_Status;
      Instance : Server_Instance;
   end record;

   type Dispatcher_Capability is limited record
      Instance : Cxx.Block.Dispatcher.Dispatcher_Capability;
   end record;

end Componolit.Interfaces.Internal.Block;
