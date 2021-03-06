--
--  @summary Component construction interface
--  @author  Johannes Kliemann
--  @date    2019-04-10
--
--  Copyright (C) 2019 Componolit GmbH
--
--  This file is part of Gneiss, which is distributed under the terms of the
--  GNU Affero General Public License version 3.
--

generic
   --  Component intialization procedure
   --
   --  @param Cap  Capability provided by the platform to use services
   with procedure Component_Construct (Cap : Capability);

   --  Component destruction procedure
   --  This procedure is called after Vacate has been called and the procedure Vacate has been called from returned.
   with procedure Component_Destruct;
package Gneiss.Component with
   SPARK_Mode,
   Abstract_State => Platform,
   Initializes => Platform
is

   --  This package must only be instantiated once
   pragma Warnings (Off, "all instances of");

   --  Status of the component on exit
   --
   --  @value Success  The component exited successfully.
   --  @value Failure  The component exited with an error.
   type Component_Status is (Success, Failure);

   --  Initial entrypoint for every component, called once on component startup
   --
   --  @param Cap  System capability
   procedure Construct (Cap : Capability) with
      Export,
      Convention => C,
      External_Name => "componolit_interfaces_component_construct";

   --  Exit method of a component.
   --
   --  This procedure is called once the platform decides to exit the component.
   procedure Destruct with
      Export,
      Convention => C,
      External_Name => "componolit_interfaces_component_destruct";

   --  Signal component
   --
   --  This procedures signals the components desire to stop to the platform. It will always return
   --  and after returning control to the platform it will decide if Destruct will be called.
   --
   --  @param Cap     System capability
   --  @param Status  Component exit status
   procedure Vacate (Cap    : Capability;
                     Status : Component_Status) with
      Global => (In_Out => Platform);

   pragma Warnings (On, "all instances of");
end Gneiss.Component;
