# coding: utf-8
require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Afipws::WSAA do
  context "generación documento tra" do
    it "debería generar xml" do
      Time.stubs(:now).returns Time.local(2001, 12, 31, 12, 00)
      xml = subject.generar_tra 'wsfe', 2400
      xml.should match_xpath "/loginTicketRequest/header/uniqueId", Time.now.to_i.to_s
      xml.should match_xpath "/loginTicketRequest/header/generationTime", "2001-12-31T11:20:00-03:00"
      xml.should match_xpath "/loginTicketRequest/header/expirationTime", "2001-12-31T12:40:00-03:00"
      xml.should match_xpath "/loginTicketRequest/service", "wsfe"
    end
  end
  
  context "firmado del tra" do
    it "debería firmar el tra usando el certificado y la clave privada" do
      key = File.read(File.dirname(__FILE__) + '/test.key')
      crt = File.read(File.dirname(__FILE__) + '/test.crt')
      tra = subject.generar_tra 'wsfe', 2400
      subject.firmar_tra(tra, key, crt).to_s.should =~ /BEGIN PKCS7/
    end
  end
  
  context "codificación del tra" do
    it "debería quitarle el header y footer" do
      subject.codificar_tra(OpenSSL::PKCS7.new).should == "MAIGAA==\n"
    end
  end
  
  context "login" do
    it "debería mandar el TRA al WS y obtener el TA" do
      ws = Afipws::WSAA.new :key => 'key', :cert => 'cert'
      ws.expects(:tra).with('key', 'cert', 'wsfe', 2400).returns('tra')
      savon.expects('loginCms').with('wsdl:in0' => 'tra').returns(:success)
      ta = ws.login
      ta[:token].should == 'PD94='
      ta[:sign].should == 'i9xDN='
      ta[:generation_time].should == Time.local(2011,01,12,18,57,04)
      ta[:expiration_time].should == Time.local(2011,01,13,06,57,04)
    end
    
    it "debería encapsular SOAP Faults" do
      subject.stubs(:tra).returns('')
      savon.stubs('loginCms').returns(:fault)
      expect { subject.login }.to raise_error Afipws::WSError, /CMS no es valido/
    end
  end
  
  context "auth" do
    before { Time.stubs(:now).returns(now = Time.local(2010,1,1)) }
    
    it "debería cachear TA" do
      subject.expects(:login).once.returns(ta = {token: 'token', sign: 'sign', expiration_time: Time.now + 60})
      subject.auth
      subject.auth
      subject.ta.should equal ta
    end
    
    it "si el TA expiró debería ejecutar solicitar uno nuevo" do
      subject.expects(:login).twice.returns(token: 't1', expiration_time: Time.now - 2).then.returns(token: 't2')
      subject.auth
      subject.ta[:token].should == 't1'
      subject.auth
      subject.ta[:token].should == 't2'
    end
  end
end
