Dieses Skript verwendet ein per config.yml konfiguriertes WFS,
beispielhaft das von geodaten-mv.de "GDI-MV - Digitale Verwaltungsgrenzen (DVG WMS)"
um die Bereichsgrenzen in Klarschiff zu importieren.

In der config.yml wird die URL zum WFS angegeben und die maximale Anzahl
von Objekten, die das WFS zurück liefern soll. Der Typename bestimmt die
Ebene, aus der die Grenze ermittelt werden soll (Kreise, Ämter oder Gemeinden).
Eine Mischung ist bisher nicht unterstützt. Die Schlüssel können z.B. mit
folgender URL ermittelt werden:
http://www.geodaten-mv.de/dienste/dvg_laiv_wfs?SERVICE=WFS&VERSION=1.1.0&REQUEST=GetFeature&TYPENAME=dvg:kreise&maxFeatures=2
http://www.geodaten-mv.de/dienste/dvg_laiv_wfs?SERVICE=WFS&VERSION=1.1.0&REQUEST=GetFeature&TYPENAME=dvg:aemter&maxFeatures=2
http://www.geodaten-mv.de/dienste/dvg_laiv_wfs?SERVICE=WFS&VERSION=1.1.0&REQUEST=GetFeature&TYPENAME=dvg:gemeinden&maxFeatures=2

Bei verschiedenen Typen sind verschiedene Filterkriterien als Schlüssel zu verwenden:

    Typ       | Schlüssel
------------------------------------------------------------------------------------------------
dvg:kreise    | Kreisschlüssel, z.B. 13 0 74 für den Landkreis Nordwestmecklenburg
dvg:aemter    | Amtsschlüssel ohne den Kreisschlüssel zu verwenden, z.B. statt 13 0 72 5259 für 
              | Amt Neubukow-Salzhaff ist nur die 5259 zu verwenden. Diese ist ebenfalls eindeutig.
dvg:gemeinden | Gemeindeschlüssel, z.B. 13 0 74 069 für die Gemeinde Roggenstorf

Unter dem Wert db werden die Verbindungsparameter zur Datenbank, die Zieltabelle
und die darin zu füllende Spalte angegeben.
