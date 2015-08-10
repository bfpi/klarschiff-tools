Dieses Skript verwendet ein per config.yml konfiguriertes WFS,
beispielhaft das von geodaten-mv.de "GDI-MV - Digitale Verwaltungsgrenzen (DVG WMS)"
um Bereichsgrenzen von Ämtern in Klarschiff als Bewirtschafter für den Zuständigkeitsfinder
zu importieren.

In der config.yml wird die URL zum WFS angegeben und die maximale Anzahl
von Objekten, die das WFS zurück liefern soll. 
Der Parameter "zugehoerig" bestimmt den Filter für die zu importierenden Ämter.
Die Selektion erfolgt durch Einschränkung auf die zu berücksichtigenden Kreise.

Unter dem Wert db werden die Verbindungsparameter zur Datenbank, die Zieltabelle
und die darin zu füllenden Spalten angegeben.
