Kommentare in Modulen: /*** ***/

Icon Files nach: 42.13/media/textures/Item_....png
3D Modelle nach: 42.13/media/models_X/WorldItems/....FBX
3d Modelltexturen nach: 42.13/media/textures/WorldItems/....png

Anwendungsfälle:
Flüssigkeiten in Rezepten
    
    Flüssigkeit von irrelevanter Quelle verbrauchen
    inputs {
        [*] mode:keep,
        -fluid 1.0 [Water],
    }
    
    Behälter mit Flüssigkeit verlangen
    inputs {
        item 1 tags[base:glassbottle] mode:keep,
        -fluid 1.0 [Water],
    }

    Behälter mit Flüssigkeit verbrauchen
    inputs {
    item 1 tags[base:glassbottle] mode:destroy,
        -fluid 1.0 [Water],
    }

    Für die Bedingung, heiße Flüssigkeiten zu nutzen:
    OnTest = RecipeCodeOnTest.hotFluidContainer,

Problembehandlungen:
Rezept wird nicht angezeigt: Syntaxfehler
Rezept kann nicht hergestellt werden, obwohl alles vorhanden ist: flags[] oder ItemMapper fehlerhaft

Kommentare:
Rezepte: /*** Text ***/
LUA: -- Text

Aktuelle Rezeptgedanken:
(/) Federn 
(/) Federn Härten

(/) Flinte -> Luftgewehr
Schrott / Schrauben -> Schrottgeschosse
(/) Gummiflocken -> Gummigeschosse
ShotgunShellMold für Gummi und Metall
Schrottgeschosse und Gummigeschosse mit Mold
(/) Small Bunch of Iron Junk
(/) Medium Bunch of Iron Junk
(/) MediumPlus Bunch of Iron Junk
(/) Large Bunch of Iron Junk
Bunch of Iron Junk als Kisten darstellen


NPK Dünger -> improvisiertes Schießpulver

Verbesserte Nagelfertigung mit Skillanforderung aus Draht
    

Tchernobill
this is how I add fluid component to the Moats at creation time
if isoObj and not isoObj:getFluidContainer() then
    local f = ComponentType.FluidContainer:CreateComponent();
    f:setCapacity(waterMax);
    GameEntityFactory.AddComponent(isoObj, true, f);
end
as you use craftRecipe you'll probably have to hook the associated action to insert it.
or maybe this works in the craftRecipe:
OnCreate = RecipeCodeOnCreate.yourModdedFunction,