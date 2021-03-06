
with Gneiss.Log;
with Gneiss.Log.Client;
with Gneiss.Timer;
with Gneiss.Timer.Client;
with Basalt.Strings;

package body Component with
   SPARK_Mode,
   Refined_State => (Component_State => Capability,
                     Platform_State  => (Log, Timer))
is
   procedure Event with
      Global => (In_Out => (Log,
                            Gneiss_Internal.Platform_State,
                            Main.Platform),
                 Input  => (Capability, Timer));

   package Gneiss_Log is new Gneiss.Log;
   package Gneiss_Timer is new Gneiss.Timer;
   package Log_Client is new Gneiss_Log.Client;
   package Timer_Client is new Gneiss_Timer.Client (Event);

   Log        : Gneiss_Log.Client_Session;
   Timer      : Gneiss_Timer.Client_Session;
   Capability : Gneiss.Capability;

   procedure Construct (Cap : Gneiss.Capability)
   is
   begin
      Capability := Cap;
      Log_Client.Initialize (Log, Capability, "log_timer");
      Timer_Client.Initialize (Timer, Capability, "timer");
      if Gneiss_Log.Initialized (Log) and then Gneiss_Timer.Initialized (Timer) then
         Timer_Client.Set_Timeout (Timer, 60.0);
         Timer_Client.Set_Timeout (Timer, 1.5);
               Log_Client.Info
                  (Log, "Time: " & Basalt.Strings.Image (Duration (Timer_Client.Clock (Timer))));
      else
         Main.Vacate (Capability, Main.Failure);
      end if;
   end Construct;

   procedure Event
   is
   begin
      if
         Gneiss_Log.Initialized (Log)
         and Gneiss_Timer.Initialized (Timer)
      then
         Log_Client.Info
            (Log, "Time: " & Basalt.Strings.Image (Duration (Timer_Client.Clock (Timer))));
         Main.Vacate (Capability, Main.Success);
      else
         Main.Vacate (Capability, Main.Failure);
      end if;
   end Event;

   procedure Destruct
   is
   begin
      Timer_Client.Finalize (Timer);
      Log_Client.Finalize (Log);
   end Destruct;

end Component;
