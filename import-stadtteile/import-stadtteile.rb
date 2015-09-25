#!/usr/bin/env ruby

require 'pg'
require 'rgeo/shapefile'

def load_config
  require 'yaml'
  YAML.load(File.open("config.yml"))
end

shp_file = ARGV[0].to_s
raise "Usage: #{ $0 } input/Stadtteile.shp" unless File.exists?(shp_file)

config = load_config
config["targets"].each do |c|
  table_name = c["table_name"]
  column_name = c["column_name"]
  PG.connect(c["db"]).tap do |conn|
    conn.exec "DELETE FROM #{ table_name }";
    conn.exec "TRUNCATE #{ table_name } RESTART IDENTITY";
    conn.prepare "p1", "INSERT INTO #{ table_name } (id, name, #{ column_name }) VALUES ($1, $2, ST_SetSRID($3::geometry, 25833))"
    RGeo::Shapefile::Reader.open(shp_file) do |shp|
      shp.each do |record|
        name = record[config["shp_column_name"]].force_encoding("ISO-8859-1").encode("UTF-8")
        conn.exec_prepared "p1", [ record.index + 1, name, record.geometry ]
      end
      shp.rewind
    end
  end
end
