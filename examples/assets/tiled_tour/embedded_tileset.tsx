<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.12.2" name="embedded_tileset" tilewidth="16" tileheight="16" tilecount="132" columns="12">
 <image source="tilesets/farm_packed.png" width="192" height="176"/>
 <tile id="14">
  <objectgroup draworder="index" id="2">
   <object id="1" x="6.09999" y="7.86476"/>
  </objectgroup>
 </tile>
 <tile id="55">
  <properties>
   <property name="int property" type="int" value="-200"/>
   <property name="tile property" value="it's a thing!"/>
  </properties>
 </tile>
 <tile id="86">
  <properties>
   <property name="tileset prop2" type="int" value="42"/>
   <property name="tileset property" type="float" value="1.34"/>
   <property name="tileset property prop" type="bool" value="true"/>
  </properties>
  <animation>
   <frame tileid="86" duration="200"/>
   <frame tileid="88" duration="400"/>
  </animation>
 </tile>
 <tile id="110">
  <objectgroup draworder="index" id="2">
   <object id="1" type="water" x="9.783" y="9.39935">
    <properties>
     <property name="depth" type="int" value="3"/>
    </properties>
   </object>
  </objectgroup>
 </tile>
</tileset>
