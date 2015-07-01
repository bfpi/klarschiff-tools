#!/usr/bin/env ruby
# coding: utf-8

require 'csv'
require 'net/http'
require 'pg'
require 'pp'
require 'rexml/document'
require 'uri'
require 'yaml'

def config
  @config ||= YAML.load(File.open("config.yml"))
end

def get_session_id(options)
  REXML::XPath.first(
    post(
      envelope.tap { |env|
        REXML::XPath.first(env, '//soapenv:Body') << REXML::Element.new("inf:startSessionRequest").tap { |e|
          e << REXML::Element.new("login").add_text(options['login'])
          e << REXML::Element.new("passwort").add_text(options['password'])
          e << REXML::Element.new("queryid").add_text(options['query_id'].to_s)
        }
      }
    ), '//sessionid'
  ).get_text
end

def post(xml)
  uri = URI(config['webservice']['url'])
  response = Net::HTTP.new(uri.host).post(uri.request_uri, xml.to_s)
  unless response.is_a? Net::HTTPOK
    raise
  end
  REXML::Document.new response.body.force_encoding("ISO-8859-1").encode("UTF-8")
end

def close_session(session_id)
  post envelope.tap { |env|
    REXML::XPath.first(env, '//soapenv:Body') << REXML::Element.new("inf:closeSessionRequest").tap { |e|
      e << REXML::Element.new("sessionid").add_text(session_id)
    }
  }
end

def envelope
  REXML::Document.new(<<-XML)
    <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:inf="http://www.tsa.de/infodienste">
      <soapenv:Header/>
      <soapenv:Body>
      </soapenv:Body>
    </soapenv:Envelope>
  XML
end

def get_ou(session_id, request_id)
  REXML::XPath.first(
    post(
      envelope.tap { |env|
        REXML::XPath.first(env, '//soapenv:Body') << REXML::Element.new("inf:getZstOrganisationseinheitenRequest").tap { |e|
          e << REXML::Element.new("sessionid").add_text(session_id)
          e << REXML::Element.new("gebietsid").add_text(config['webservice']['region_id'].to_s)
          e << REXML::Element.new("anliegenid").add_text(request_id.to_s)
        }
      }
    ), '//BEZEICHNUNG'
  ).get_text
end

class Object
  def blank?
    respond_to?(:empty?) ? !!empty? : !self
  end

  def present?
    !blank?
  end

  def presence
    self if present?
  end
end

class String
  def sanitize_ldap
    self.gsub(/[ ,\/]/, '_').
      gsub(/ä/, 'ae').gsub(/Ä/, 'Ae').
      gsub(/ö/, 'oe').gsub(/Ö/, 'Oe').
      gsub(/ü/, 'ue').gsub(/Ü/, 'Ue').
      gsub(/ß/, 'ss').
      gsub(/_{2,}/, '_')
  end
end

class Category
  attr_accessor :session_id, :name, :type, :detail, :responsible_name, :subcategories, :anliegen

  def initialize(options = {})
    self.subcategories = []
    options.each { |attr, value| send :"#{ attr }=", value }
  end

  def responsible
    @responsible ||= anliegen ? get_ou(session_id, anliegen).to_s.strip : responsible_name
  end

  def responsible_key
    responsible.downcase.sanitize_ldap if responsible
  end
end

def categories_from_csv(filename, session_id)
  Array.new.tap do |categories|
    CSV.foreach(filename, headers: true) do |l|
      name = l[0].strip
      type = l[1].strip rescue nil
      responsible_name = l[2].strip rescue nil
      anliegen = l[3].to_i if l[3].present?
      detail = (l[4].presence || 'keine').strip

      if type.present?
        # Hauptkategorie
        categories << Category.new(session_id: session_id, name: name, type: type, detail: detail)
      else
        # Unterkategorie
        categories.last.subcategories << Category.new(
          session_id: session_id, name: name, type: type, detail: detail, 
          responsible_name: responsible_name, anliegen: anliegen)
      end
    end
  end
end

def db_conn(conf)
  PG.connect(conf).tap do |conn|
    def conn.get_new_id
      self.exec("SELECT COALESCE(MAX(id), 0) + 1 AS id FROM klarschiff_kategorie").first['id']
    end

    def conn.create_category(id, type, name, detail)
      self.exec_params <<-SQL, [id, type.downcase, name, detail]
        INSERT INTO klarschiff_kategorie(id, typ, "name", naehere_beschreibung_notwendig)
        VALUES($1, $2, $3, $4)
      SQL
    end

    def conn.create_subcategory(id, parent, name, detail)
      self.exec_params <<-SQL, [id, parent, name, detail]
        INSERT INTO klarschiff_kategorie(id, parent, "name", naehere_beschreibung_notwendig)
        VALUES($1, $2, $3, $4)
      SQL
    end

    def conn.create_category_responsibility(id, responsible)
      self.exec_params <<-SQL, [id, responsible]
        INSERT INTO klarschiff_kategorie_initial_zustaendigkeiten(kategorie, initial_zustaendigkeiten)
        VALUES($1, $2)
      SQL
    end

    def conn.update_category(id, name, detail)
      self.exec_params <<-SQL, [id, name, detail]
        UPDATE klarschiff_kategorie
        SET geloescht = FALSE, "name" = $2, naehere_beschreibung_notwendig = $3
        WHERE id = $1
      SQL
    end
  end
end

begin
  raise "No file for csv import given" unless filename = ARGV[0]
  session_id = get_session_id(config['webservice'])

  groups = {}

  conn = db_conn(config['db']['connection'])
  conn.exec <<-SQL
    UPDATE klarschiff_kategorie SET geloescht = TRUE;
    DELETE FROM klarschiff_kategorie_initial_zustaendigkeiten
  SQL
  categories_from_csv(filename, session_id).each do |cat|
    cat.subcategories.each do |sub|
      if res = conn.exec_params(<<-SQL, [cat.type, cat.name, sub.name]).first
        SELECT k.id, k.parent
        FROM klarschiff_kategorie k
          JOIN klarschiff_kategorie hk ON k.parent = hk.id
        WHERE hk.typ ILIKE $1 AND TRIM(hk."name") ILIKE $2 and TRIM(k."name") ILIKE $3
        SQL
        conn.update_category res['parent'], cat.name, cat.detail
        conn.update_category res['id'], sub.name, sub.detail
        conn.create_category_responsibility res['id'], sub.responsible_key
      elsif res = conn.exec_params(<<-SQL, [cat.type, cat.name]).first
        SELECT id
        FROM klarschiff_kategorie
        WHERE parent IS NULL AND typ ILIKE $1 AND TRIM("name") ILIKE $2
        SQL
        conn.update_category res['id'], cat.name, cat.detail
        sub_id = conn.get_new_id
        conn.create_subcategory sub_id, res['id'], sub.name, sub.detail
        conn.create_category_responsibility sub_id, sub.responsible_key
      else
        id = conn.get_new_id
        conn.create_category id, cat.type, cat.name, cat.detail
        sub_id = conn.get_new_id
        conn.create_subcategory sub_id, id, sub.name, sub.detail
        conn.create_category_responsibility sub_id, sub.responsible_key
      end
      if (val = groups[sub.responsible_key]) && val != sub.responsible
        raise "Different responsibilities for same key: #{ sub.responsible_key }: " \
          "#{ groups[sub.responsible_key] }, #{ sub.responsible }"
      elsif sub.responsible_key.blank?
        raise "Empty responsibility key for category: #{ cat.name } => #{ sub.name }"
      else
        groups[sub.responsible_key] = sub.responsible
      end
    end
  end
  puts "Required groups in ldap:"
  groups.sort.each { |cn, displayname| puts " #{ cn } : #{ displayname }" }
ensure
  close_session session_id if session_id
  conn.close if conn
end
