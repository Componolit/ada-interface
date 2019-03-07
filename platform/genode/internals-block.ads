
with Cxx;
with Cxx.Block.Client;

package Internals.Block is

   type Private_Data is new Cxx.Genode_Uint8_T_Array (1 .. 16);
   Null_Data : Private_Data := (others => 0);
   type Device is limited record
      Instance : Cxx.Block.Client.Class;
   end record;

end Internals.Block;
