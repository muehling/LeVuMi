# -*- encoding : utf-8 -*-
require 'net/http'
class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  before_action :check_login, except: [:welcome, :login, :signup]
  before_action :check_accept, except: [:welcome, :login, :signup, :accept, :static, :logout]

  def login
    u = User.find_by_email(params[:email])
    if u != nil && u.account_type!=-1
      if u.authenticate(params[:password])
        session[:user_id] = u.id
        session[:student_id] = nil
        @login_student = nil
        @login_user = u
        @user = u
        news = News.new_items(u)
        u.last_login = Time.now
        u.save
        #if u.complete?
          redirect_to user_groups_path(u), notice: news.empty? ? "Eingeloggt als #{u.email}" : news.join("<br/><br/>")
        #else
        #  redirect_to edit_user_path(u), notice: "Eingeloggt als #{u.email} <br/> Bitte vervollständigen Sie noch Ihre persönlichen Daten, Sie helfen uns damit bei der wissenschaftlichen Begleitung von Levumi!" +  (news.empty? ? "" : "<br/>" + news.join("<br/><br/>"))
        #end
      else
        redirect_to root_url, notice: 'Benutzername oder Passwort falsch!'
      end
    else
      redirect_to root_url, notice: 'Benutzername oder Passwort falsch!'
    end
  end

  def logout
    if(!session[:user_id].nil?)
      session[:user_id] = nil
      @login_user = nil
    end
    redirect_to root_url
  end

  def welcome
    if params.has_key?(:page)
      render params[:page], :layout => 'bare'
    else
      render 'welcome', :layout => 'bare'
    end
  end

  def signup
    if params["name"].blank? || params["email"].blank? || params["state"].blank?
      flash['notice'] = "Bitte füllen Sie alle Felder aus!"
      render 'signup', layout: 'bare' and return
    end
    if params["account_type"] == "0" && (params["school"].blank? || params["occupation"].blank?)
      flash['notice'] = "Bitte füllen Sie alle Felder aus!"
      render 'signup', layout: 'bare' and return
    end
    if params["account_type"] == "1" && (params["school"].blank?)
      flash['notice'] = "Bitte füllen Sie alle Felder aus!"
      render 'signup', layout: 'bare' and return
    end
    password = Digest::SHA1.hexdigest(rand(36**8).to_s(36))[1..6]
    u = User.find_by_email(params[:email])
    unless u.nil? || u.account_type != -1     #Versuch, sich mit einem alten Account erneut zu registrieren => alten Account löschen.
      u.destroy                               #TODO: Doch lieber "Fallback User" für Daten
    end
    @user = User.new(email: params[:email], name: params[:name], account_type: params[:account_type], password: password, password_confirmation: password)
    @user.school = params["school"] if params.has_key?("school")
    @user.occupation = params["occupation"] if params.has_key?("occupation")
    @user.state = params["state"] if params.has_key?("state")
    if @user.save
      UserMailer.registered(@user.email, @user.name, password).deliver_later
      render 'registered', layout: 'bare'
    else
      error = ''
      unless @user.errors['email'].blank?
        error = 'E-Mail Adresse ungültig oder bereits registriert!'
      end
      flash['notice'] = error
      render 'signup', layout: 'bare'
    end
  end

  def accept
    @login_user.tcaccept = DateTime.now
    @login_user.save
    redirect_to user_groups_path(@login_user), notice: 'Viel Spaß bei der Benutzung von Levumi!'
  end

  def static
    render params[:page]
  end

  def export
    unless !@login_user.nil? && @login_user.hasCapability?('export')
      redirect_to root_url
    end
    @tests = Test.all
    @users = User.all
  end

  def transfer_data
    client_data = JSON.parse(params[:data])
    test_klasse = JSON.parse(params[:test_klasse])
    data_to_transfer = {}

    #prepare user for tranfer
    user_transfer =  {id: @login_user.id, email: @login_user.email, password_digest: @login_user.password_digest,
                      institution: @login_user.school, account_type: @login_user.account_type, state: @login_user.state}
    data_to_transfer[:user] = user_transfer

    #prepare groups for tranfer
    groups_transfer = {}
    students_transfer = {}
    assessments_transfer = {}
    groups = @login_user.groups.where('(archive IS NULL OR archive = false) AND name != "Testklasse"')
    groups_transfer[-1] = {label: 'Testklasse', key:test_klasse['key'], auth_token: test_klasse['token']}
    groups.each do |g|
      if !g.demo
        groups_transfer[g.id] = {label: g.name, key: client_data[g.id.to_s]['key'], auth_token: client_data[g.id.to_s]['token']}
        students_transfer[g.id] = {}
        assessments_transfer[g.id] = {}
      end
    end
    data_to_transfer[:groups] = groups_transfer


    students = Student.where(group_id:groups)
    #prepare students for transfer
    students.each do |s|
      if s.specific_needs.nil?
        sen = nil
      elsif s.specific_needs == 0
        sen = 0
      elsif s.specific_needs == 1
        sen = 1
      elsif s.specific_needs == 2
        sen = 2
      elsif s.specific_needs == 3
        sen = 0
      else
        sen = 4
      end
      students_transfer[s.id]= {group_id: s.group_id, name: client_data[s.group_id.to_s]['students'][s.id.to_s], login: s.login,
                                     gender: (s.gender.nil? ? nil : (s.gender ? 1 : 0)), birthmonth: s.birthdate,
                                     migration: (s.migration.nil? ? nil : (s.migration ? 1 : 0)), sen: sen}
    end
    data_to_transfer[:students] = students_transfer
    #prepare assessments for transfer and merge relevant data from test
    assessments = Assessment.where(group_id:groups)
    test = Test.where('archive != true AND shorthand!= "PF1" AND shorthand!= "ZR" AND shorthand!= "PF2" AND shorthand!= "PF3" AND shorthand!= "ZF1" AND shorthand!= "ZF2" AND shorthand!= "ZF3"').pluck(:id, :shorthand)
    test_transfer = {}
    items_test = {}
    lookup_table= {
        "SL2a" => {
            "del" => "I1",
            "ho" => "I2",
            "Rei" => "I3",
            "Wu" => "I4",
            "nen" => "I5",
            "pi" => "I6",
            "en" => "I7",
            "lei" => "I8",
            "Tau" => "I9",
            "sen" => "I10",
            "fer" => "I11",
            "men" => "I12",
            "de" => "I13",
            "wa" => "I14",
            "Dau" => "I15",
            "Pa" => "I16",
            "Lei" => "I17",
            "hu" => "I18",
            "Sau" => "I19",
            "wei" => "I20",
            "da" => "I21",
            "hen" => "I22",
            "Pi" => "I23",
            "we" => "I24",
            "hau" => "I25",
            "Tei" => "I26",
            "De" => "I27",
            "pa" => "I28",
            "fen" => "I29",
            "der" => "I30",
            "Wei" => "I31",
            "Hu" => "I32",
            "po" => "I33",
            "Sei" => "I34",
            "We" => "I35",
            "tau" => "I36",
            "du" => "I37",
            "fei" => "I38",
            "Ho" => "I39",
            "Rau" => "I40",
            "sei" => "I41",
            "wu" => "I42",
            "Da" => "I43",
            "hei" => "I44",
            "Po" => "I45",
            "rau" => "I46",
            "Wa" => "I47",
            "Hei" => "I48",
            "Du" => "I49",
            "sau" => "I50",
            "len" => "I51",
            "rei" => "I52",
            "Do" => "I53",
            "ha" => "I54",
            "tei" => "I55",
            "Hau" => "I56",
            "do" => "I57",
            "lau" => "I58",
            "Ha" => "I59",
            "dei" => "I60",
            "mer" => "I61",
            "dau" => "I62"
        },
        "SL3" => {
            "Stä" => "I1",
            "Je" => "I2",
            "feu" => "I3",
            "Schä" => "I4",
            "Zü" => "I5",
            "Euch" => "I6",
            "zä" => "I7",
            "beu" => "I8",
            "zeu" => "I9",
            "jä" => "I10",
            "vei" => "I11",
            "spi" => "I12",
            "ßen" => "I13",
            "ja" => "I14",
            "Vi" => "I15",
            "Sta" => "I16",
            "Zö" => "I17",
            "vö" => "I18",
            "zö" => "I19",
            "je" => "I20",
            "zü" => "I21",
            "jau" => "I22",
            "spe" => "I23",
            "qua" => "I24",
            "spä" => "I25",
            "za" => "I26",
            "spei" => "I27",
            "keu" => "I28",
            "Zei" => "I29",
            "Jä" => "I30",
            "Zi" => "I31",
            "vo" => "I32",
            "Ze" => "I33",
            "Sti" => "I34",
            "Stö" => "I35",
            "ßer" => "I36",
            "euch" => "I37",
            "Hex" => "I38",
            "Qua" => "I39",
            "Feu" => "I40",
            "stau" => "I41",
            "auch" => "I42",
            "spu" => "I43",
            "neu" => "I44",
            "geu" => "I45",
            "Jau" => "I46",
            "spa" => "I47",
            "Zau" => "I48",
            "Scheu" => "I49",
            "Keu" => "I50",
            "sti" => "I51",
            "va" => "I52",
            "Schü" => "I53",
            "Vei" => "I54",
            "zu" => "I55",
            "qui" => "I56",
            "Schö" => "I57",
            "Va" => "I58",
            "ze" => "I59",
            "ju" => "I60",
            "stu" => "I61",
            "zi" => "I62",
            "Ja" => "I63",
            "stä" => "I64",
            "Zu" => "I65",
            "vi" => "I66",
            "Stei" => "I67",
            "schä" => "I68",
            "Eu" => "I69",
            "spü" => "I70",
            "Vö" => "I71",
            "schö" => "I72",
            "Beu" => "I73",
            "Auch" => "I74",
            "stei" => "I75",
            "hex" => "I76",
            "Stu" => "I77",
            "Neu" => "I78",
            "Spu" => "I79",
            "Ju" => "I80",
            "scheu" => "I81",
            "Vo" => "I82",
            "schü" => "I83",
            "Jo" => "I84",
            "seu" => "I85",
            "Za" => "I86",
            "Spei" => "I87",
            "jo" => "I88",
            "zei" => "I89",
            "Spi" => "I90",
            "xi" => "I91",
            "Sto" => "I92",
            "Zeu" => "I93",
            "Ty" => "I94",
            "Spa" => "I95",
            "cheu" => "I96",
            "Spä" => "I97",
            "py" => "I98",
            "eu" => "I99",
            "Ste" => "I100",
            "ße" => "I101",
            "ste" => "I102",
            "Py" => "I103",
            "Stau" => "I104",
            "Zä" => "I105",
            "Seu" => "I106",
            "Qui" => "I107",
            "sta" => "I108",
            "zau" => "I109",
            "stö" => "I110",
            "ty" => "I111",
            "Spü" => "I112",
            "Spe" => "I113",
            "sto" => "I114"
        },
        "PL2a" => {
            "pofen" => "I1",
            "halei" => "I2",
            "wapa" => "I3",
            "teitau" => "I4",
            "delsau" => "I5",
            "eidel" => "I6",
            "wemer" => "I7",
            "leisau" => "I8",
            "senhau" => "I9",
            "mendel" => "I10",
            "rawu" => "I11",
            "fenha" => "I12",
            "nenrau" => "I13",
            "teilei" => "I14",
            "sendu" => "I15",
            "heira" => "I16",
            "laulen" => "I17",
            "wenen" => "I18",
            "derho" => "I19",
            "pihau" => "I20",
            "enmer" => "I21",
            "senra" => "I22",
            "rauwa" => "I23",
            "daufer" => "I24",
            "heiwa" => "I25",
            "lenrei" => "I26",
            "teisei" => "I27",
            "weido" => "I28",
            "ferha" => "I29",
            "pawa" => "I30",
            "dofen" => "I31",
            "laudel" => "I32",
            "detei" => "I33",
            "wawu" => "I34",
            "haulen" => "I35",
            "derde" => "I36",
            "reidel" => "I37",
            "lensen" => "I38",
            "wadu" => "I39",
            "mertau" => "I40",
            "hauha" => "I41",
            "rahei" => "I42",
            "deldo" => "I43",
            "teisen" => "I44",
            "wamen" => "I45",
            "pahau" => "I46",
            "heifen" => "I47",
            "fenpi" => "I48",
            "derda" => "I49",
            "hura" => "I50",
            "weiha" => "I51",
            "saupi" => "I52",
            "wupi" => "I53",
            "laumer" => "I54",
            "dode" => "I55",
            "huwa" => "I56",
            "pader" => "I57",
            "duwu" => "I58",
            "ratei" => "I59",
            "tausau" => "I60",
            "hoder" => "I61",
            "wuda" => "I62",
            "datau" => "I63",
            "hupi" => "I64",
            "pihei" => "I65",
            "weiwa" => "I66",
            "haura" => "I67",
            "teimer" => "I68",
            "dellei" => "I69",
            "weipo" => "I70",
            "lenho" => "I71",
            "huhei" => "I72",
            "merpo" => "I73",
            "dodau" => "I74",
            "reipa" => "I75",
            "poder" => "I76",
            "welen" => "I77",
            "dara" => "I78",
            "hupo" => "I79",
            "wepa" => "I80",
            "pawei" => "I81",
            "reihau" => "I82",
            "dohau" => "I83",
            "wuhei" => "I84",
            "reilau" => "I85",
            "haunen" => "I86",
            "merrei" => "I87",
            "lentau" => "I88",
            "huda" => "I89",
            "padau" => "I90",
            "weipa" => "I91",
            "delei" => "I92",
            "teidu" => "I93",
            "heiho" => "I94",
            "mermen" => "I95",
            "seiwei" => "I96",
            "wadau" => "I97",
            "dauha" => "I98",
            "reien" => "I99",
            "hendau" => "I100",
            "parau" => "I101",
            "waho" => "I102",
            "teifen" => "I103",
            "wetei" => "I104",
            "heidau" => "I105",
            "derpo" => "I106",
            "saulei" => "I107",
            "daudel" => "I108",
            "hauhen" => "I109",
            "weisau" => "I110",
            "leihei" => "I111",
            "ender" => "I112",
            "pahen" => "I113",
            "wapi" => "I114",
            "laupa" => "I115",
            "weda" => "I116",
            "hensei" => "I117",
            "durau" => "I118",
            "mensei" => "I119",
            "eirei" => "I120",
            "lauhu" => "I121",
            "heisau" => "I122",
            "reiwu" => "I123",
            "ferwa" => "I124",
            "weipi" => "I125",
            "dusau" => "I126",
            "nende" => "I127",
            "heiha" => "I128",
            "pilau" => "I129",
            "depa" => "I130",
            "menen" => "I131",
            "hurau" => "I132",
            "derdo" => "I133",
            "wuwa" => "I134",
            "hauwu" => "I135",
            "teiha" => "I136",
            "rauho" => "I137",
            "hopi" => "I138",
            "dado" => "I139",
            "deldu" => "I140",
            "rauwei" => "I141",
            "hudu" => "I142",
            "leilau" => "I143",
            "wuwei" => "I144",
            "dupi" => "I145",
            "pafen" => "I146",
            "wulau" => "I147",
            "humer" => "I148",
            "mentau" => "I149",
            "dudel" => "I150"
        },
        "PL3a" => {
            "hexef" => "I1",
            "schönu" => "I2",
            "pysa" => "I3",
            "scheuli" => "I4",
            "tyli" => "I5",
            "hexaf" => "I6",
            "steisi" => "I7",
            "zale" => "I8",
            "jese" => "I9",
            "schöse" => "I10",
            "zamo" => "I11",
            "geusi" => "I12",
            "beuno" => "I13",
            "eufo" => "I14",
            "pyfu" => "I15",
            "speife" => "I16",
            "geufu" => "I17",
            "jale" => "I18",
            "zile" => "I19",
            "vofa" => "I20",
            "stafi" => "I21",
            "xila" => "I22",
            "volu" => "I23",
            "jemo" => "I24",
            "scheuse" => "I25",
            "zema" => "I26",
            "geula" => "I27",
            "zisa" => "I28",
            "steiru" => "I29",
            "zuri" => "I30",
            "steime" => "I31",
            "zili" => "I32",
            "euni" => "I33",
            "tyma" => "I34",
            "hexun" => "I35",
            "eure→““" => "I36",
            "beulu" => "I37",
            "qualo" => "I38",
            "tyru" => "I39",
            "scheufu" => "I40",
            "pyme" => "I41",
            "vano" => "I42",
            "zasi" => "I43",
            "vasu" => "I44",
            "zifu" => "I45",
            "spesu" => "I46",
            "xilo" => "I47",
            "feune" => "I48",
            "schöfo" => "I49",
            "tyso" => "I50",
            "neune" => "I51",
            "stana" => "I52",
            "vise" => "I53",
            "stame" => "I54",
            "zeru" => "I55",
            "steifo" => "I56",
            "quafu" => "I57",
            "vifo" => "I58",
            "jeli" => "I59",
            "spelo" => "I60",
            "feuma" => "I61",
            "neumi" => "I62",
            "speilu" => "I63",
            "vore" => "I64",
            "pyri" => "I65",
            "spele" => "I66",
            "feuli" => "I67",
            "speino" => "I68",
            "xisu" => "I69",
            "zufe" => "I70",
            "vari" => "I71",
            "feufu" => "I72",
            "zele" => "I73",
            "xime" => "I74",
            "zeni" => "I75",
            "speimi" => "I76",
            "jara" => "I77",
            "stalo" => "I78",
            "beumi" => "I79",
            "zusu" => "I80",
            "vane" => "I81",
            "zanu" => "I82",
            "feuso" => "I83",
            "jenu" => "I84",
            "scheura" => "I85",
            "vono" => "I86",
            "stasu" => "I87",
            "vala" => "I88",
            "quani" => "I89",
            "neulo" => "I90",
            "geuso" => "I91",
            "eusu" => "I92",
            "pyno" => "I93",
            "zafa" => "I94",
            "vume" => "I95",
            "tyne" => "I96",
            "beusa" => "I97",
            "neusa" => "I98",
            "schöla" => "I99",
            "xine" => "I100",
            "hexol" => "I101",
            "beure" => "I102",
            "jasu" => "I103",
            "speira" => "I104",
            "vomi" => "I105",
            "steila" => "I106",
            "vimi" => "I107",
            "geume" => "I108",
            "speni" => "I109",
            "vufo" => "I110",
            "spema" => "I111",
            "zula" => "I112",
            "quase" => "I113",
            "vuni" => "I114",
            "schöme" => "I115",
            "euma" => "I116",
            "zefo" => "I117",
            "hexim" => "I118",
            "zino" => "I119",
            "vura" => "I120",
            "zumo" => "I121",
            "quara" => "I122",
            "vuru" => "I123",
            "jamo" => "I124",
            "vila" => "I125",
            "jafi" => "I126",
            "viru" => "I127",
            "neufu" => "I128",
            "scheuno" => "I129",
            "jera" => "I130"
        },
        "SEL4" => {
            "backt" => "I1",
            "Schere" => "I2",
            "Während" => "I3",
            "Büro" => "I4",
            "spitz" => "I5",
            "weil" => "I6",
            "Bilder" => "I7",
            "böse" => "I8",
            "bevor" => "I9",
            "mit" => "I10",
            "dicke" => "I11",
            "runde" => "I12",
            "Blumen" => "I13",
            "spricht" => "I14",
            "Durch" => "I15",
            "Tür" => "I16",
            "Anstatt" => "I17",
            "kauft" => "I18",
            "Vogel" => "I19",
            "scheint" => "I20",
            "für" => "I21",
            "Baby" => "I22",
            "hungrig" => "I23",
            "weder" => "I24",
            "aber" => "I25",
            "schmeckt" => "I26",
            "Augen" => "I27",
            "Wasser" => "I28",
            "Nachdem" => "I29",
            "lustigen" => "I30",
            "schnelle" => "I31",
            "Schuhe" => "I32",
            "Auf" => "I33",
            "neues" => "I34",
            "Bett" => "I35",
            "außer" => "I36",
            "wohne" => "I37",
            "Haus" => "I38",
            "von" => "I39",
            "isst" => "I40",
            "über" => "I41",
            "Beine" => "I42",
            "Freunde" => "I43",
            "Biene" => "I44",
            "schläft" => "I45",
            "süß" => "I46",
            "wegen" => "I47",
            "Sonne" => "I48",
            "Hase" => "I49",
            "gut" => "I50",
            "Zwischen" => "I51",
            "Frösche" => "I52",
            "wartest" => "I53",
            "Wenn" => "I54",
            "sammeln" => "I55",
            "Sobald" => "I56",
            "Enten" => "I57",
            "fleißig" => "I58",
            "Schwester" => "I59",
            "unter" => "I60"
        }
    }

    test.each do |t|
      test_transfer[t[0]] = {shorthand:t[1]}
      items = Item.where(test_id: t[0]).pluck(:id, :difficulty, :shorthand, :itemtext)
      count = 1

      items.each do |i|
        if (t[1] == 'SW2' && i[2] == 'gerade') ||(t[1] == 'SEL4' && i[2] == 'In') || (t[1] == 'SL2a' && (i[2] == 'Ra' ||i[2] == 'ra')) ||
            (t[1] == 'SL3' && (i[2] == 'Quä' ||i[2] == 'quä')) || (t[1] == 'SL4' && i[2] == 'tri') || (t[1] == 'PL2a' && i[2] == 'seiei') || (t[1] == 'PL3a' && i[2] == 'eure')||
            (t[1] == 'TS0' && i[2] != 'Fertig') || ((t[1] == 'WSK' || t[1] == 'WS1') && (i[2] == 'Hallo' ||i[2] == 'Erklärung' ||i[2] == 'Löschen und Audio' ||i[2] == 'Hinweis' ||i[2] == 'Beispiel' ||i[2] == 'Beispiele' ||i[2] == 'Ich beginne' ||i[2] == 'Ende')) ||
            (i[2] == 'Preparation') || (i[2] == 'Ende')
        else
          if t[1] == 'SL2a' || t[1] == 'SL3' || t[1] == 'PL2a' || t[1] == 'PL3a' || t[1] == 'SEL4'
            items_test[i[0]] = {id: lookup_table[t[1]][i[2]], group: i[1], itemtext: i[2]}
          else
            items_test[i[0]] = {id: "I" + count.to_s, group: i[1], itemtext: i[2], zr_only: i[3]}
          end
          count += 1
        end
      end
    end

    measurements = Measurement.where(assessment_id: assessments).pluck(:id, :assessment_id)
    measurements_transfer = {}
    measurements.each do |m|
      if measurements_transfer[m[1]].nil?
        measurements_transfer[m[1]] = [m[0]]
      else
        measurements_transfer[m[1]] = measurements_transfer[m[1]] + [m[0]]
      end
    end
    assessments.each do |a|
      if !test_transfer[a.test_id].nil?
        assessments_transfer[a.id] = {test_id: a.test_id,group_id: a.group_id, shorthand: test_transfer[a.test_id][:shorthand], measurement_ids: measurements_transfer[a.id]}
      end
    end
    data_to_transfer[:assessments] = assessments_transfer

    #prepare results for transfer
    results = Result.where(student_id: students)
    results_transfer = []
    results.each do |r|
      if !test_transfer[r.measurement.assessment.test_id].nil?
        if !r.responses[0].nil?
          prior_result = r.getPriorResult()
          if prior_result == -1 || r.total == prior_result
            total = 0
          elsif r.total > prior_result
            total  = 1
          else
            total = -1
          end
          data = []
          report = {trend:total, positive:[], negative:[]}
          p_items = []
          n_items = []
          #SEL2 und 4
          ada_cor = 0
          avp_cor = 0
          avk_cor = 0
          ada_cor_items = ""
          avp_cor_items = ""
          avk_cor_items = ""
          ada_fal = 0
          avp_fal = 0
          avk_fal = 0
          ada_fal_items = ""
          avp_fal_items = ""
          avk_fal_items = ""
          #SEL6
          coh_cor = 0
          complex_str_cor = 0
          inf_cor = 0
          coh_cor_items = ""
          complex_str_cor_items = ""
          inf_cor_items = ""
          coh_fal = 0
          complex_str_fal = 0
          inf_fal = 0
          coh_fal_items = ""
          complex_str_fal_items = ""
          inf_fal_items = ""
          sum = 0
          correct_items = ""
          false_items = ""
          n_sum = 0

          r.items.each_with_index do |item, index|
            if !items_test[item].nil?
              if r.extra_data['times'].nil?
                data += [{item: items_test[item][:id], group: items_test[item][:group]}]
              else
                if r.extra_data['answers'].nil?
                  if r.extra_data['times'][index].nil?
                    data += [{item: items_test[item][:id], group: items_test[item][:group], time: 'NA'}]
                  else
                    data += [{item: items_test[item][:id], group: items_test[item][:group], time: r.extra_data['times'][index]}]
                  end

                else
                  if r.extra_data['times'][index].nil?
                    data += [{item: items_test[item][:id], group: items_test[item][:group], answer: 'NA', time: 'NA'}]
                  else
                    data += [{item: items_test[item][:id], group: items_test[item][:group], answer: r.extra_data['answers'][index] ,time: r.extra_data['times'][index]}]
                  end
                end
              end
              if r.responses[index] == 1
                if r.measurement.assessment.test.shorthand == "SEL6"
                  sum += 1
                  if items_test[item][:group] == 1
                    complex_str_cor += 1
                    if complex_str_cor_items == ''
                    complex_str_cor_items += items_test[item][:itemtext]
                    else
                      complex_str_cor_items += ', ' + items_test[item][:itemtext]
                    end
                  elsif items_test[item][:group] == 2
                    inf_cor += 1
                    if inf_cor_items ==''
                    inf_cor_items += items_test[item][:itemtext]
                    else
                      inf_cor_items += ', ' + items_test[item][:itemtext]
                    end
                  else
                    coh_cor += 1
                    if coh_cor_items ==''
                    coh_cor_items += items_test[item][:itemtext]
                    else
                      coh_cor_items += ', ' + items_test[item][:itemtext]
                    end
                  end
                elsif r.measurement.assessment.test.shorthand == "SEL4"
                  sum += 1
                  if items_test[item][:group] == 1
                    ada_cor += 1
                    if ada_cor_items == ''
                      ada_cor_items += items_test[item][:itemtext]
                    else
                      ada_cor_items += ', ' + items_test[item][:itemtext]
                    end
                  elsif items_test[item][:group] == 2
                    avp_cor += 1
                    if avp_cor_items ==''
                      avp_cor_items += items_test[item][:itemtext]
                    else
                      avp_cor_items += ', ' + items_test[item][:itemtext]
                    end
                  else
                    avk_cor += 1
                    if avk_cor_items ==''
                      avk_cor_items += items_test[item][:itemtext]
                    else
                      avk_cor_items += ', ' + items_test[item][:itemtext]
                    end
                  end
                elsif r.measurement.assessment.test.shorthand == "SEL2"
                  sum += 1
                  if items_test[item][:group] == 1
                    ada_cor += 1
                    if ada_cor_items == ''
                      ada_cor_items += items_test[item][:itemtext]
                    else
                      ada_cor_items += ', ' + items_test[item][:itemtext]
                    end
                  else
                    avp_cor += 1
                    if avp_cor_items ==''
                      avp_cor_items += items_test[item][:itemtext]
                    else
                      avp_cor_items += ', ' + items_test[item][:itemtext]
                    end
                  end
                else
                  sum += 1
                  if r.measurement.assessment.test.shorthand == "ZR"
                    variables = items_test[item][:zr_only].split(",")
                    correctAnswer = variables[4]
                    possibleAnswers = variables[0,4].join(',')
                    if correct_items == ""
                      correct_items += possibleAnswers.sub!('-', "(" + correctAnswer + ")")
                    else
                      correct_items += ', ' + possibleAnswers.sub!('-', "(" + correctAnswer + ")")
                    end
                  else
                    if correct_items == ""
                      correct_items += items_test[item][:itemtext]
                    else
                      correct_items += ', ' + items_test[item][:itemtext]
                    end
                  end
                end
                p_items += [data.last[:item]]
              elsif r.responses[index] == 0
                if r.measurement.assessment.test.shorthand == "SEL6"
                  if items_test[item][:group] == 1
                    complex_str_fal += 1
                    if complex_str_fal_items == ''
                      complex_str_fal_items += items_test[item][:itemtext]
                    else
                      complex_str_fal_items += ', ' + items_test[item][:itemtext]
                    end
                  elsif items_test[item][:group] == 2
                    inf_fal += 1
                    if inf_fal_items == ''
                      inf_fal_items += items_test[item][:itemtext]
                    else
                      inf_fal_items += ', ' + items_test[item][:itemtext]
                    end
                  else
                    coh_fal += 1
                    if coh_fal_items == ''
                      coh_fal_items += items_test[item][:itemtext]
                    else
                      coh_fal_items += ', ' + items_test[item][:itemtext]
                    end
                  end
                elsif r.measurement.assessment.test.shorthand == "SEL4"
                  if items_test[item][:group] == 1
                    ada_fal += 1
                    if ada_fal_items == ''
                      ada_fal_items += items_test[item][:itemtext]
                    else
                      ada_fal_items += ', ' + items_test[item][:itemtext]
                    end
                  elsif items_test[item][:group] == 2
                    avp_fal += 1
                    if avp_fal_items == ''
                      avp_fal_items += items_test[item][:itemtext]
                    else
                      avp_fal_items += ', ' + items_test[item][:itemtext]
                    end
                  else
                    avk_fal += 1
                    if avk_fal_items == ''
                      avk_fal_items += items_test[item][:itemtext]
                    else
                      avk_fal_items += ', ' + items_test[item][:itemtext]
                    end
                  end
                elsif r.measurement.assessment.test.shorthand == "SEL2"
                  if items_test[item][:group] == 1
                    ada_fal += 1
                    if ada_fal_items == ''
                      ada_fal_items += items_test[item][:itemtext]
                    else
                      ada_fal_items += ', ' + items_test[item][:itemtext]
                    end
                  else
                    avp_fal += 1
                    if avp_fal_items == ''
                      avp_fal_items += items_test[item][:itemtext]
                    else
                      avp_fal_items += ', ' + items_test[item][:itemtext]
                    end
                  end
                else
                  n_sum +=1
                  if r.measurement.assessment.test.shorthand == "ZR"
                    variables = items_test[item][:zr_only].split(",")
                    correctAnswer = variables[4]
                    possibleAnswers = variables[0,4].join(',')
                    if false_items == ""
                      false_items += possibleAnswers.sub!('-', "(" + correctAnswer + ")") + '<' + r.extra_data['answers'][index]  + '>'
                    else
                      false_items += ', ' + possibleAnswers.sub!('-', "(" + correctAnswer + ")") + '<' + r.extra_data['answers'][index]  + '>'
                    end
                  else
                    if false_items == ""
                      false_items += items_test[item][:itemtext]
                    else
                      false_items += ', ' + items_test[item][:itemtext]
                    end
                  end
                end
                n_items += [data.last[:item]]
              end
            end
          end
          results = nil
          if r.measurement.assessment.test.shorthand == "SEL6"
            coherence = '<strong>Anzahl richtig gelöster Items:</strong> '+coh_cor.to_s+'<br/><strong>Richtig gelöste Items: </strong><br/>'+coh_cor_items+'<br/><br/><strong>Anzahl falsch gelöster Items:</strong> '+coh_fal.to_s+'<br/><strong>Falsch gelöste Items:</strong><br/>'+coh_fal_items
            complex_structure = '<strong>Anzahl richtig gelöster Items:</strong> '+complex_str_cor.to_s+'<br/><strong>Richtig gelöste Items: </strong><br/>'+complex_str_cor_items+'<br/><br/><strong>Anzahl falsch gelöster Items:</strong> '+complex_str_fal.to_s+'<br/><strong>Falsch gelöste Items:</strong><br/>'+complex_str_fal_items
            inferenz = '<strong>Anzahl richtig gelöster Items:</strong> '+inf_cor.to_s+'<br/><strong>Richtig gelöste Items: </strong><br/>'+inf_cor_items+'<br/><br/><strong>Anzahl falsch gelöster Items:</strong> '+inf_fal.to_s+'<br/><strong>Falsch gelöste Items:</strong><br/>'+inf_fal_items
            results = {'V1': sum, 'V2': {'RI':''+sum.to_s + ' von 93', 'KOMS': complex_structure, 'INF': inferenz, 'KO': coherence, 'LG': r.total, 'LGM': "-"},'V3': {'SUM':sum ,'RI':''+sum.to_s + ' von 93', 'KOMS': complex_structure, 'INF': inferenz, 'KO': coherence, 'LG': r.total, 'LGM': "-"} }
          elsif r.measurement.assessment.test.shorthand == "SEL4"
            ada = '<strong>Anzahl richtig gelöster Items:</strong> '+ada_cor.to_s+'<br/><strong>Richtig gelöste Items: </strong><br/>'+ada_cor_items+'<br/><br/><strong>Anzahl falsch gelöster Items:</strong> '+ada_fal.to_s+'<br/><strong>Falsch gelöste Items:</strong><br/>'+ada_fal_items
            avp = '<strong>Anzahl richtig gelöster Items:</strong> '+avp_cor.to_s+'<br/><strong>Richtig gelöste Items: </strong><br/>'+avp_cor_items+'<br/><br/><strong>Anzahl falsch gelöster Items:</strong> '+avp_fal.to_s+'<br/><strong>Falsch gelöste Items:</strong><br/>'+avp_fal_items
            avk = '<strong>Anzahl richtig gelöster Items:</strong> '+avk_cor.to_s+'<br/><strong>Richtig gelöste Items: </strong><br/>'+avk_cor_items+'<br/><br/><strong>Anzahl falsch gelöster Items:</strong> '+avk_fal.to_s+'<br/><strong>Falsch gelöste Items:</strong><br/>'+avk_fal_items
            results = {'V1': sum, 'V2': {'RI':''+sum.to_s + ' von 60', 'ADA': ada, 'AVP': avp, 'AVK': avk, 'LG': r.total, 'LGM': "-"},'V3': {'SUM':sum ,'RI':''+sum.to_s + ' von 60', 'ADA': ada, 'AVP': avp, 'AVK': avk, 'LG': r.total, 'LGM': "-"} }
          elsif r.measurement.assessment.test.shorthand == "SEL2"
            ada = '<strong>Anzahl richtig gelöster Items:</strong> '+ada_cor.to_s+'<br/><strong>Richtig gelöste Items: </strong><br/>'+ada_cor_items+'<br/><br/><strong>Anzahl falsch gelöster Items:</strong> '+ada_fal.to_s+'<br/><strong>Falsch gelöste Items:</strong><br/>'+ada_fal_items
            avp = '<strong>Anzahl richtig gelöster Items:</strong> '+avp_cor.to_s+'<br/><strong>Richtig gelöste Items: </strong><br/>'+avp_cor_items+'<br/><br/><strong>Anzahl falsch gelöster Items:</strong> '+avp_fal.to_s+'<br/><strong>Falsch gelöste Items:</strong><br/>'+avp_fal_items
            results = {'V1': sum, 'V2': {'RI':''+sum.to_s + ' von 66', 'ADA': ada, 'AVP': avp, 'LG': r.total, 'LGM': "-"},'V3': {'SUM':sum ,'RI':''+sum.to_s + ' von 66', 'ADA': ada, 'AVP': avp, 'LG': r.total, 'LGM': "-"} }
          elsif r.measurement.assessment.test.shorthand == "TS0"
            results = {'V1': 1 }
            p_item = ["I1"]
            n_items = []
          else
            correct = '<strong>Anzahl richtig gelöster Items:</strong> '+sum.to_s+'<hr style="margin-top:0; margin-bottom:0"/>'+correct_items
            wrong = '<strong>Anzahl falsch gelöster Items:</strong> '+n_sum.to_s+'<hr style="margin-top:0; margin-bottom:0"/>'+false_items
            results = {'V1': sum, 'V2': {'RGI': correct, 'FGI': wrong, 'LG': r.total, 'LGM': "-"},'V3': {'SUM':sum ,'RGI': correct, 'FGI': wrong, 'LG': r.total, 'LGM': "-"} }
          end
          report[:positive] = p_items
          report[:negative] = n_items
          results_transfer = results_transfer + [{student_id: r.student_id, measurement_id: r.measurement_id, test_date: r.measurement.date,
                                                  results: results, report:report,
                                                  data:data, created_at: r.created_at}]
        end
      end

    end
    data_to_transfer[:results] = results_transfer


    #send data to new Levumi
    uri = URI.parse('https://www.levumi.de:4433/import')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri.request_uri, initheader = {'Content-Type' =>'application/json'})

    data_to_send = {data: data_to_transfer}
    request.body = data_to_send.to_json

    request["Content-Type"] = "application/json"
    request["Data-Type"] = 'json'
    response = JSON.parse(http.request(request).body)

    if response['status']
      @login_user.transferred = true
      @login_user.save
      @login_user = nil
      session.delete(:user_id)
      redirect_to 'https://www.levumi.de:4433/start'

      #flash[:notice] = 'Ihre Daten wurden erfolgreich übertragen. Viel Spaß bei der Benutzung von Levumi 2.0!'
      #respond_to do |format|
      #  format.js   {}
      #end
    end
  end

  private
  #check if user is logged in
  def check_login
    if session[:user_id].nil? && session[:student_id].nil?
      redirect_to root_url, notice: 'Bitte einloggen!'
    elsif !session[:student_id].nil?
      @login_student = Student.find(session[:student_id])
     else
      @login_user = User.find(session[:user_id])
    end
  end

  #check if user accepted the letter of agreement
  def check_accept
    if !@login_user.nil? && @login_user.tcaccept.nil?
      render 'accept'
    end
  end


end
