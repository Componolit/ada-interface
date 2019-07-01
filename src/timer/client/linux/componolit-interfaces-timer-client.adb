
with System;

package body Componolit.Interfaces.Timer.Client with
   SPARK_Mode => Off
is

   function Create return Client_Session
   is
   begin
      return (Instance => System.Null_Address);
   end Create;

   function Initialized (C : Client_Session) return Boolean
   is
      use type System.Address;
   begin
      return C.Instance /= System.Null_Address;
   end Initialized;

   procedure Initialize (C : in out Client_Session; Cap : Componolit.Interfaces.Types.Capability)
   is
      procedure C_Initialize (Session    : in out System.Address;
                              Capability :        Componolit.Interfaces.Types.Capability;
                              Callback   :        System.Address) with
         Import,
         Convention => C,
         External_Name => "timer_client_initialize";
   begin
      C_Initialize (C.Instance, Cap, Event'Address);
   end Initialize;

   function Clock (C : Client_Session) return Time
   is
      pragma Unreferenced (C);
      function C_Clock return Time with
         Volatile_Function,
         Import,
         Convention => C,
         External_Name => "timer_client_clock";
   begin
      return C_Clock;
   end Clock;

   procedure Set_Timeout (C : in out Client_Session;
                          D :        Duration)
   is
      procedure C_Timeout (Session : System.Address;
                           Dur     : Duration) with
         Import,
         Convention => C,
         External_Name => "timer_client_set_timeout";
   begin
      C_Timeout (C.Instance, D);
   end Set_Timeout;

   procedure Finalize (C : in out Client_Session)
   is
      procedure C_Finalize (Session : in out System.Address) with
         Import,
         Convention => C,
         External_Name => "timer_client_finalize";
   begin
      C_Finalize (C.Instance);
   end Finalize;

end Componolit.Interfaces.Timer.Client;
