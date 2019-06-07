
with Musinfo;
with Debuglog.Types;

package Componolit.Interfaces.Muen with
   SPARK_Mode
is

   type Session_Type is (None, Log);

   type Session_Element (Session : Session_Type := None) is record
      case Session is
         when None =>
            null;
         when Log =>
            Name           : Musinfo.Name_Type;
            Memregion      : Musinfo.Memregion_Type;
            Message_Index  : Debuglog.Types.Message_Index;
            Message_Buffer : Debuglog.Types.Data_Type;
      end case;
   end record;

   type Session_Index is new Natural;
   Invalid_Index : constant Session_Index := Session_Index'First;

   type Session_List is array (Session_Index range 1 .. 64) of Session_Element;

   function Name_To_String (Name : Musinfo.Name_Type) return String;

   function String_To_Name (Name : String) return Musinfo.Name_Type;

   Session_Registry : Session_List := (others => Session_Element'(Session => None));

end Componolit.Interfaces.Muen;
