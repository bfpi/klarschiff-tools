#!/usr/bin/env ruby

def load_config
  require 'yaml'
  YAML.load(File.open("config.yml"))
end

input = ARGV[0].to_s
raise "Usage: #{ $0 } input/adressen.txt" unless File.exists?(input)

config = load_config

require 'pg'

PG.connect(config['db']).tap do |conn|
  conn.exec <<SQL
DROP TABLE IF EXISTS import_adressen;

CREATE TABLE import_adressen (
  nba CHAR (1), oi CHAR(16), qua CHAR(1), lan CHAR(2), rbz CHAR(1), krs CHAR(2),
  gmd CHAR(3), ott CHAR(4), sss CHAR(5), hnr VARCHAR(100), adz VARCHAR(100),
  eee CHAR(12), nnn CHAR(12), stn VARCHAR(255), plz CHAR(5), 
  onm VARCHAR(255), zon VARCHAR(255), pot VARCHAR(255), str VARCHAR(255), void VARCHAR(1)
);

COPY import_adressen 
  FROM '#{ File.absolute_path(input) }'
  CSV 
  DELIMITER ';' 
  ENCODING 'LATIN1';

TRUNCATE ort, adresse, strasse RESTART IDENTITY;

INSERT INTO ort(name)
SELECT DISTINCT onm FROM import_adressen;

INSERT INTO strasse(name, ortsteil_id)
SELECT DISTINCT stn, ot.id from import_adressen a INNER JOIN ortsteil ot ON ot.name = a.pot INNER JOIN ort o ON a.onm = o.name;

INSERT INTO adresse(strasse_id, hausnummer, hausnummerzusatz, geom)
SELECT
  s.id, hnr::INTEGER, adz, ST_SetSRID(ST_MakePoint(
    REPLACE(eee, ',', '.')::FLOAT - 33000000,
    REPLACE(nnn, ',', '.')::FLOAT
  ), 25833)
  FROM import_adressen a 
    INNER JOIN strasse s ON s.name = a.stn
    INNER JOIN ortsteil ot ON ot.name = a.pot
    INNER JOIN ort o ON a.onm = o.name;

UPDATE strasse SET geom = sub.geom FROM (
  SELECT sub2.id, st_makeline(sub2.geom) AS geom
  FROM (
    SELECT s.id, a.geom
    FROM strasse s
    INNER JOIN adresse a ON a.strasse_id = s.id
    ORDER BY s.id, a.hausnummer
  ) sub2
  GROUP BY sub2.id
) sub WHERE sub.id = strasse.id;

DROP TABLE IF EXISTS import_adressen;
SQL
end
