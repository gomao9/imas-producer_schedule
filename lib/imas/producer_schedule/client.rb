# frozen_string_literal: true

require 'open-uri'
require 'icalendar'
require 'nokogiri'
require 'yaml'
require 'active_support'

module Imas::ProducerSchedule
  class Client
    REGULAR_ARTICLE = [
      /^デレラジ$/,
      /^THE IDOLM@STER STATION!!\+$/,
      /^ラジオdeアイマchu!!$/,
      /^アイマスタジオ$/,
      /^【CINDERELLA Night】デレラジA$/,
      /^CINDERELLA PARTY!$/,
      /^THE IDOLM@STER STATION!!!$/,
      /^ミリオンラジオ！$/,
      /^アイドルマスター シンデレラガールズ .{1,2}話放送$/,
      /^アイドルマスター シンデレラガールズ .{1,2}話配信（バンダイチャンネル）$/,
      /^【CINDERELLA Night】アイドルマスター シンデレラガールズ .{1,2}話配信（ニコ生）$/,
      /^「リスアニ！TV」TVAシンデレラガールズコーナー$/,
      /^315プロNight!$/,
      /^アイドルマスター .{1,2}話放送（再放送）$/,
      /^アイドルマスター シンデレラガールズ　.{1,2}話放送（再放送）$/,
      /^デレラジ☆（スター）$/,
      /^TVアニメ「アイドルマスター シンデレラガールズ」2nd SEASON$/,
      /^シンデレラガールズ劇場 第.{1,2}話放送$/,
      /^アニメ アイドルマスター SideM 第.{1,2}話放送$/,
      /^アイドルマスター シャイニーカラーズ はばたきラジオステーション$/,
      /^アニメ　アイドルマスター SideM　理由あってMini!　第.{1,2}話放送$/,
      /^THE IDOLM@STER MUSIC ON THE RADIO$/
    ].freeze
    HEADER_OFFSET = 3
    TZID = 'Asia/Tokyo'
    DEFAULT_MONTH_PATH = File.join(File.expand_path('../../..', __dir__), 'months.yml')

    def initialize(month_path = DEFAULT_MONTH_PATH)
      @months = ::YAML.load_file(month_path)
    end

    def output_cal(output_dir = '.')
      # カレンダー情報定義
      cals = [
        { name: 'プロデューサー予定表',
          file: 'schedule.ics',
          test: ->(_schedule) { true } },
        { name: '定期配信番組除外版',
          file: 'schedule_irregular.ics',
          test: ->(schedule) { REGULAR_ARTICLE.none? { |re| schedule[:article] =~ re } } },
        { name: '定期配信番組のみ',
          file: 'schedule_regular.ics',
          test: ->(schedule) { REGULAR_ARTICLE.any? { |re| schedule[:article] =~ re } } },
        { name: '発売日',
          file: 'release_day.ics',
          test: ->(schedule) { schedule[:time] == '発売日' } },
        { name: 'イベント',
          file: 'event.ics',
          test: ->(schedule) { schedule[:genre].include? 'イベント' } },
        { name: 'ニコ生',
          file: 'nico_live.ics',
          test: ->(schedule) { schedule[:genre].include? 'ニコ生' } }
      ]

      # タイトル・タイムゾーン設定
      cals.each do |cal|
        calendar = Icalendar::Calendar.new
        calendar.append_custom_property('X-WR-CALNAME;VALUE=TEXT', cal[:name])
        set_timezone calendar
        cal[:cal] = calendar
      end

      @months.each do |year, str, num, type|
        url = case type
              when 'a' then "http://idolmaster.jp/schedule/#{year}#{str}.php"
              when 'b' then "http://idolmaster.jp/schedule/#{year}/#{str}.php"
              when 'c' then "http://idolmaster.jp/schedule/?ey=#{year}&em=#{str}"
              end
        schedules = parse_calendar url
        month = num

        # イベント設定
        day = nil # いらないかも？
        schedules.each do |s|
          e = Icalendar::Event.new

          # s[:day]がnilならば直前の日付と同じ
          day = s[:day] || day

          # 日付時刻
          if s[:from].nil?
            e.dtstart = Icalendar::Values::Date.new(format('%04d%02d%02d', year, month, day), 'tzid' => TZID)
          else
            st_tm = to_datetime(year, month, day, *split_time(s[:from]))
            ed_tm = st_tm
            unless s[:to].nil?
              ed_tm = to_datetime(year, month, day, *split_time(s[:to]))
            end
            e.dtstart = st_tm
            e.dtend   = ed_tm
          end

          # ジャンル
          e.append_custom_property('X-GENRE;VALUE=TEXT', s[:genre])
          # リンク
          e.append_custom_property('X-LINK;VALUE=TEXT', s[:link]) if s[:link]
          # 時間
          e.append_custom_property('X-TIME;VALUE=TEXT', s[:time])

          # サマリ
          e.summary     = s[:article]
          # 詳細
          e.description = s[:description]

          # カレンダーへ追加
          cals.each do |c|
            c[:cal].add_event e if c[:test].call(s)
          end
        end
      end

      # カレンダー発行
      cals.each do |c|
        c[:cal].publish
        open(File.join(output_dir, c[:file]), 'w') { |f| f.write(c[:cal].to_ical) }
      end
    end

    private

    def to_schedule(tr)
      # ジャンル
      genre = tr.at('.//td[@class="genre2"]').try(:text)
      # 内容・リンク
      article = tr.at('.//td[@class="article2"]').try(:text)
      link = tr.at('.//td[@class="article2"]/a').try(:[], 'href')
      # 日付
      day = tr.at('.//td[@class="day2"]/img')
      day ||= tr.at('.//td[@class="day"]/img')
      day = day['src'][-6..-5].to_i if day
      # 時刻
      time = tr.at('.//td[@class="time2"]').try(:text)
      # From-To
      from, to = time.try(:tr, '１２３４５６７８９０：', '1234567890:').try(:scan, /\d\d:\d\d/)
      # 出演者
      performance = tr.at('.//td[@class="performance2"]/img').try(:[], 'alt')
      # 詳細
      description = "時間：#{time}\n"
      description += "出演：#{performance}\n"
      description += "記事：#{article}\n"
      description += "リンク：#{link}\n"

      # ハッシュ生成
      unless article.blank?
        { day: day, time: time, genre: genre.try(:strip), article: article, link: link, from: from, to: to, description: description }
      end
    end

    def parse_calendar(url)
      html = URI.open(url, &:read)
      charset = 'utf-8'

      # htmlをパースしてオブジェクトを生成
      doc = Nokogiri::HTML.parse(html, nil, charset)
      doc.xpath('//*[@id="tabelarea"]/table/tr').drop(HEADER_OFFSET).map do |tr|
        to_schedule(tr)
      end.compact
    end

    def to_datetime(year, month, day, hour, min)
      if hour >= 24
        hour -= 24
        exceed = true
      end
      datetime = DateTime.civil(year, month, day, hour, min)
      datetime += 1.day if exceed
      Icalendar::Values::DateTime.new datetime, 'tzid' => TZID
    end

    def split_time(hm_string)
      hm_string.split(':').map(&:to_i)
    end

    def set_timezone(cal)
      cal.timezone do |t|
        t.tzid = TZID
        t.standard do |s|
          s.tzoffsetfrom = '+0900'
          s.tzoffsetto   = '+0900'
          s.tzname       = 'JST'
          s.dtstart      = '19700101T000000'
        end
      end
    end
  end
end
