--
--  @summary Memory interface declarations
--  @author  Johannes Kliemann
--  @date    2020-01-13
--
--  Copyright (C) 2020 Componolit GmbH
--
--  This file is part of Gneiss, which is distributed under the terms of the
--  GNU Affero General Public License version 3.
--
with Gneiss_Internal;

generic
   pragma Warnings (Off, "* is not referenced");
   type Context is limited private;
   --  Read the ROM data
   --
   --  @param Session  Client session
   --  @param Data     ROM contents
   with procedure Read (Session : in out Client_Session;
                        Data    :        Buffer;
                        Ctx     : in out Context);
   pragma Warnings (On, "* is not referenced");
package Gneiss.Rom.Client with
   SPARK_Mode
is

   --  Initialize client session
   --
   --  @param Session  Client session
   --  @param Cap      System capability
   --  @param Label    Session label
   --  @param Idx      Session index
   procedure Initialize (Session : in out Client_Session;
                         Cap     :        Gneiss.Capability;
                         Label   :        String;
                         Idx     :        Session_Index := 1) with
      Global => (In_Out => Gneiss_Internal.Platform_State);

   --  Update the rom and call Read
   --
   --  @param Session  Client session
   generic
      with function Contract (Ctx : Context) return Boolean;
   procedure Update (Session : in out Client_Session;
                     Ctx     : in out Context) with
      Pre    => Initialized (Session)
                and then Contract (Ctx),
      Post   => Initialized (Session)
                and then Contract (Ctx),
      Global => (In_Out => Gneiss_Internal.Platform_State);

   --  Close the session
   --
   --  @param Session  Client session
   procedure Finalize (Session : in out Client_Session) with
      Post   => not Initialized (Session),
      Global => (In_Out => Gneiss_Internal.Platform_State);

end Gneiss.Rom.Client;
