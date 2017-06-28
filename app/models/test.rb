# -*- encoding : utf-8 -*-

#TODO-A: Teststruktur überdenken?

require 'spreadsheet'

class Test < ActiveRecord::Base
  has_many :items, :dependent => :destroy
  has_many :assessments, :dependent => :destroy

  validates_presence_of :name
  validates_presence_of :subject
  validates_presence_of :construct
  validates_presence_of :level
  after_create :set_defaults

  def set_defaults
    self.archive ||= false
  end

  def content_items
    self.items.where(itemtype: 0).order(:id)
  end

  #TODO: Konsequent verwenden!
  def intro_items
    self.items.where("itemtype < ?", 0).order(:itemtype)
  end

  #TODO: Konsequent verwenden!
  def outro_items
    self.items.where("itemtype > ?", 0).order(:itemtype)
  end

  def draw_items(first)
    itemset = intro_items
    enditems = outro_items
    if first
      itemset = itemset + content_items
    else
      len.times do
        remaining = items - (itemset + enditems)
        itemset = itemset + [remaining.sample]
      end
    end
    itemset = itemset + enditems
    return itemset.map{|i| i.id}
  end

  def len_info
    return "#{len} Items"
  end

  def type_info
    return 'Test'
  end

  def view_info
    return 'Test'
  end

  def long_name
    return name + ' - ' + level + ' (' + subject + ' - ' + construct + ')' + (archive ? ' - veraltet':'')
  end

  def short_name
    return name + ' - ' + level + (archive ? ' (veraltet)':'')
  end

  def export
    measurements = Measurement.where(:assessment => Assessment.where(:test => self))
    results = Result.where(:measurement => measurements)
    students = Student.where(:id => results.uniq.pluck(:student_id))

    book = Spreadsheet::Workbook.new

    sheet = book.create_worksheet :name => 'Items'
    sheet.row(0).concat Item.xls_headings
    i = 1
    items.each do |it|
      sheet.row(i).concat it.to_a
      i = i+1
    end

    sheet = book.create_worksheet :name => 'SuS'
    sheet.row(0).concat Student.xls_headings
    i = 1
    students.find_each do |s|
      if (s.group.export)
        sheet.row(i).concat s.to_a
        i = i+1
      end
    end

    sheet = book.create_worksheet :name => 'Alle Messungen'
    sheet.row(0).concat %w(Schüler/in Messzeitpunkt Klassen-Id Benutzer-Id)
    itemset = items.pluck(:id)
    sheet.row(0).concat itemset
    i = 1
    results.find_each do |r|
      if (r.measurement.assessment.group.export)
        sheet.row(i).push r.student.id
        sheet.row(i).push r.measurement.date.to_date.strftime("%d.%m.%Y")
        sheet.row(i).push r.measurement.assessment.group.id
        sheet.row(i).push r.measurement.assessment.group.user.id
        sheet.row(i).concat r.to_a(itemset)
        i = i+1
      end
    end

    measurements.sort_by { |a| a.date}.each do |m|
      if (m.assessment.group.export)
        sheet = book.create_worksheet :name => "Messung #{m.id}"
        sheet.row(0).push 'Datum'
        sheet.row(0).push m.date.to_date.strftime("%d.%m.%Y")
        sheet.row(1).push 'Benutzer-Id'
        sheet.row(1).push m.assessment.group.user.id
        sheet.row(2).push 'Klassen-Id'
        sheet.row(2).push m.assessment.group.id

        sheet.row(3).concat %w(Student)
        itemset = items.pluck(:id)
        sheet.row(3).concat itemset
        i = 4
        m.results.each do |r|
          sheet.row(i).push r.student.id
          sheet.row(i).concat r.to_a(itemset)
          i = i+1
        end
      end
    end

    temp = Tempfile.new('levumi')
    temp.close
    book.write temp.path
    return temp.path
  end

  def self.exportAll
    measurements = Measurement.all
    results = Result.all
    students = Student.all
    assessments = Assessment.all

    book = Spreadsheet::Workbook.new  
    sheet1 = book.create_worksheet name: 'items'
    sheet1.row(0).concat Item.xls_headings
    row = 1
    tests = []


    sheets = {}
    assessments.sort_by { |a| a.created_at}.each do |ass|
      test = ass.test
      if !sheets.key? test.name
        sheet = book.create_worksheet :name => "#{test.name}"
        sheet.row(0).push "Student"
        sheet.row(0).concat test.items.pluck(:id)
        sheets[test.name] = sheet
      end
    end

    
    measurements.sort_by{|a| a.date}.each do |m|
      if (m.assessment.group.export and Result.where(:measurement =>m).size > 0)
        test = m.assessment.test
        sheet = sheets[test.name]
        row = sheet.last_row_index + 1
        sheet.row(row).push "Datum"
        sheet.row(row).push m.date.to_date.strftime("%d.%m.%Y")
        sheet.row(row).push " "
        sheet.row(row).push "Klassen-Id"
        sheet.row(row).push m.assessment.group.id
        sheet.row(row).push " "
        sheet.row(row).push "Test"
        sheet.row(row).push test.name
        sheet.row(row).push test.short_info
        sheet.row(row).push "Level"
        sheet.row(row).push test.level
        row = row + 1
        sheet.row(row).push " "
        sheet.row(row).concat test.items.pluck(:id)
        row = row + 1 
        itemset = test.items.pluck(:id)
        m.results.each do |r|
          sheet.row(row).push r.student.id
          sheet.row(row).concat r.to_a(itemset)
          row = row + 1
        end
      end
    end

=begin    testnames = []
    measurements.sort_by { |a| a.date}.each do |m|
      if (m.assessment.group.export and Result.where(:measurement =>m).size > 0)
        test = m.assessment.test
        sheet = book.create_worksheet :name => "Messung #{m.id}"
        sheet.row(0).push 'Datum'
        sheet.row(0).push m.date.to_date.strftime("%d.%m.%Y")
        sheet.row(1).push 'Benutzer-Id'
        sheet.row(1).push m.assessment.group.user.id
        sheet.row(2).push 'Klassen-Id'
        sheet.row(2).push m.assessment.group.id
        sheet.row(3).push 'Test'
        sheet.row(3).push test.name
        sheet.row(4).concat %w(Student)
        # save id of each test to show their items
        tests = tests << test.id

        items = m.assessment.test.items
        itemset = items.pluck(:id)
        sheet.row(4).concat itemset
        i = 5
        m.results.each do |r|
          sheet.row(i).push r.student.id
          sheet.row(i).concat r.to_a(itemset)
          i = i+1
        end
      end
    end

    # get unique id's of tests to show the items once at the top of the sheet
    sheet1.row(row).concat tests.uniq
=end
    temp = Tempfile.new('levumi')
    temp.close
    book.write temp.path
    return temp.path
  end
end
