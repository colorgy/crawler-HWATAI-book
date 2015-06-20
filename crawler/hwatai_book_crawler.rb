require 'crawler_rocks'
require 'iconv'
require 'pry'

require 'thread'
require 'thwait'

class HwataiBookCrawler
  include CrawlerRocks::DSL

  def initialize
    @search_url = "http://www.hwatai.com.tw/webc/html/book/02.aspx"
  end

  def books
    @books = []
    @threads = []
    @detail_threads = []

    visit @search_url
    page_num = @doc.css('.pw').map{|pw| pw.text.to_i}.max

    (1..page_num).each do |i|
      sleep(1) until (
        @threads.delete_if { |t| !t.status };  # remove dead (ended) threads
        @threads.count < (ENV['MAX_THREADS'] || 5)
      )
      @threads << Thread.new do
        puts i
        r = RestClient.get "#{@search_url}?Page=#{i}"
        doc = Nokogiri::HTML(r.to_s)

        doc.css('.newslist li').each do |row|
          @detail_threads.delete_if { |t| !t.status };
          @detail_threads << Thread.new do
            img_rel_url = row.css('.newspic img').map{|img| img[:src]}.first
            external_image_url = img_rel_url ? URI.join(@search_url, img_rel_url).to_s : nil

            url = row.css('.more a').map{|href| href[:href]}.first
            url && url = URI.join(@search_url, url).to_s

            name = nil; category = nil; author = nil; isbn = nil; edition = nil; price = nil;
            publisher = nil;
            row.css('.newstable tr').map{|tr| tr.text.strip.gsub(/\s+/, ' ')}.delete_if {|txt| txt.empty?}.each do |attribute|
              attribute.match(/書           名：(?<n>.+)/) {|m| name ||= m[1].strip}
              attribute.match(/作    譯    者：(?<n>.+)/) {|m| author ||= m[1].strip}
              attribute.match(/I S B N - 13：(?<n>.+)/) {|m| isbn ||= m[1].strip}
              attribute.match(/類           別：(?<n>.+)/) {|m| category ||= m[1].strip}
              attribute.match(/定           價：(?<n>.+)/) {|m| price ||= m[1].gsub(/[^\d]/, '').to_i}
            end

            if url && rr = RestClient.get(url)
              detail_doc = Nokogiri::HTML(rr)

              detail_doc.css('.booktext tr').map{|tr| tr.text.strip.gsub(/\s+/, ' ')}.delete_if {|txt| txt.empty?}.each do |attribute|
                attribute.match(/出     版     商：(?<n>.+)/) {|m| publisher ||= m[1].strip}
                attribute.match(/版             次：(?<n>.+)/) {|m| edition ||= m[1].to_i}
              end
            end

            @books << {
              name: name,
              author: author,
              category: category,
              isbn: isbn,
              price: price,
              edition: edition,
              publisher: publisher,
              url: url,
              external_image_url: external_image_url
            }
            print "|"
          end # end detail thread

          ThreadsWait.all_waits(*@detail_threads)
        end # end each row
      end # end threads do
    end # end each page

    ThreadsWait.all_waits(*@threads)
    @books
  end
end

cc = HwataiBookCrawler.new
File.write('hwatai_books.json', JSON.pretty_generate(cc.books))
