
package body Cxx.Block.Dispatcher with
   SPARK_Mode => Off
is

   procedure Dispatch (This : Class;
                       Cap  : Dispatcher_Capability)
   is
      procedure D (C : Dispatcher_Capability) with
         Import,
         Address => This.Handler;
   begin
      D (Cap);
   end Dispatch;

end Cxx.Block.Dispatcher;
