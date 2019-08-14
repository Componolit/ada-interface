
with Componolit.Interfaces.Types;
with Componolit.Interfaces.Component;
with Componolit.Interfaces.Block;
with Componolit.Interfaces.Block.Client;
with Componolit.Interfaces.Block.Dispatcher;
with Componolit.Interfaces.Block.Server;

package Component is

   procedure Construct (Cap : Componolit.Interfaces.Types.Capability);
   procedure Destruct;

   package Main is new Componolit.Interfaces.Component (Construct, Destruct);

   type Byte is mod 2 ** 8;
   subtype Unsigned_Long is Long_Integer range 0 .. Long_Integer'Last;
   type Buffer is array (Unsigned_Long range <>) of Byte;
   type Request_Index is mod 8;

   package Block is new Componolit.Interfaces.Block (Byte, Unsigned_Long, Buffer, Request_Index);

   procedure Event;
   procedure Dispatch (I : Block.Dispatcher_Instance;
                       C : Block.Dispatcher_Capability) with
      Pre => Block.Initialized (I);
   function Initialized (S : Block.Server_Instance) return Boolean;
   procedure Initialize_Server (S : Block.Server_Instance; L : String; B : Block.Byte_Length) with
      Pre => not Initialized (S);
   procedure Finalize_Server (S : Block.Server_Instance) with
      Pre => Initialized (S);
   function Block_Count (S : Block.Server_Instance) return Block.Count with
      Pre => Initialized (S);
   function Block_Size (S : Block.Server_Instance) return Block.Size with
      Pre => Initialized (S);
   function Writable (S : Block.Server_Instance) return Boolean with
      Pre => Initialized (S);

   procedure Write (C :     Block.Client_Instance;
                    I :     Request_Index;
                    D : out Buffer) with
      Pre => Block.Initialized (C);

   procedure Read (C : Block.Client_Instance;
                   I : Request_Index;
                   D : Buffer) with
      Pre => Block.Initialized (C);

   package Block_Client is new Block.Client (Event, Read, Write);
   package Block_Server is new Block.Server (Event,
                                             Block_Count,
                                             Block_Size,
                                             Writable,
                                             Initialized,
                                             Initialize_Server,
                                             Finalize_Server);
   package Block_Dispatcher is new Block.Dispatcher (Block_Server, Dispatch);

end Component;
