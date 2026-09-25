<?xml version="1.0" encoding="UTF-8"?>
<!-- A pit, as a Tiled tileset over pits.png: drawn here, by
     tools/draw_pit_tiles.rb. See README.md.

     Both tiles have the class `gap`, which is what makes a cell holding one a
     gap to RGame::Engine::TileMap: no floor, so a walker falls into it and a
     hop crosses it. Tile 0 is the pit, and tile 1 its north edge, for a gap
     cell with floor north of it. -->
<tileset version="1.10" tiledversion="1.10.2" name="pits" tilewidth="16" tileheight="16" tilecount="2" columns="2">
 <image source="pits.png" width="32" height="16"/>
 <tile id="0" class="gap"/>
 <tile id="1" class="gap"/>
</tileset>
