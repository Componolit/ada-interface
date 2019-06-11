
package body Componolit.Interfaces.Component with
   SPARK_Mode => Off
is

   procedure Construct (Capability : Componolit.Interfaces.Types.Capability)
   is
   begin
      Component_Construct (Capability);
   end Construct;

   procedure Vacate (Cap    : Componolit.Interfaces.Types.Capability;
                     Status : Component_Status)
   is
      procedure C_Vacate (C : Componolit.Interfaces.Types.Capability;
                          S : Integer) with
         Import,
         Convention => C,
         External_Name => "componolit_interfaces_component_vacate";
   begin
      if Status = Success then
         C_Vacate (Cap, 0);
      else
         C_Vacate (Cap, 1);
      end if;
   end Vacate;

   procedure Destruct
   is
   begin
      Component_Destruct;
   end Destruct;

end Componolit.Interfaces.Component;
