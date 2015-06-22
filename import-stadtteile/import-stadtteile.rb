#!/usr/bin/env ruby

def load_config
  require 'yaml'
  YAML.load(File.open("config.yml"))
end

shp_file = ARGV[0].to_s
raise "Usage: #{ $0 } input/Stadtteile.shp" unless File.exists?(shp_file)

config = load_config
config["targets"].each do |c|
  drop_table = %{psql -c 'DROP TABLE IF EXISTS "#{ config["import_table_name"] }"' #{ c["database"] }}
  `#{ drop_table }`

  `shp2pgsql -W LATIN1 #{ shp_file } "#{ config["import_table_name"] }" | psql #{ c["database"]}`

  # DELETE FROM, damit Trigger greifen und TRUNCATE um die Sequenz zurück zu setzen 
  puts `psql #{ c["database"]} <<SQL
  DELETE FROM "#{ c["table_name"] }";
  TRUNCATE "#{ c["table_name"] }" RESTART IDENTITY;
  INSERT INTO "#{ c["table_name"] }" (id, name, "#{ c["column_name"] }")
  SELECT gid, "#{ config["shp_column_name"] }", ST_TRANSFORM(ST_SETSRID(geom, 2398), 25833) FROM "#{ config["import_table_name"] }";
SQL`
  `#{ drop_table }`
end
