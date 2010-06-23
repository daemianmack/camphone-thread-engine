#!/usr/bin/ruby

require 'rubygems'
require 'mms2r'
require 'tmail'
require 'ostruct'
require 'mysql'
require 'net/smtp'
require 'mechanize'


@opts = OpenStruct.new(
                       :dbhost         => "localhost",
                       :db             => "database",
                       :dbuser         => "camphone",
                       :dbpass         => "camphone_password",
                       :forum_id       => 100,
                       :thread_id      => 2000,
                       :upload_to      => "http://upload.example.com/",
                       :cookie         => "/Users/daemian/bin/camphone/cookie",
                       :uploaded_xpath => "//div[@id='success']",
                       :smtphost       => "localhost",
                       :logfile        => "camphone_mails.log",
                       :reply_bcc      => "user@example.com",
                       :reply_from     => "camphone_bot@example.com"
                       )




def log(message)
  logfile = File.open(@opts.logfile, "a") do |f|
    f << Time.now.strftime('%a %b %d %I:%M%p') + ": " + message + "\n"
  end
end

def handle_registrations(mms, email)
  username = IO.readlines(mms.default_text.path)
  username = username.to_s.gsub(/<\/?[^>]*>/, "").split[0].to_s  # Get first word: username.
  log "Username: #{username}"
  password = IO.readlines(mms.default_text.path)
  password = password.to_s.gsub(/<\/?[^>]*>/, "").split[1].to_s  # Get second word: password.
  log "Password: #{password}"
  q = @dbh.prepare("insert into camphone_users (username, identifier, password) values (?, ?, ?)")
  if q.execute(username.downcase, mms.number, password)
    send_mail(email, "This device is now registered.")
  end
end

def find_username(mms)
  passwords = []
  if mms.default_text
    passwords << IO.readlines(mms.default_text.path).join.split.slice!(0..0).to_s.split("Attachment")[0] # Get first word and password.
    mms.media['text/plain'].each do |text|
      # Some carriers attach the user message as a file. Loop through all files, grab the first word, and we'll try each.
      passwords << IO.readlines(text).join.split.slice!(0..0).to_s.split("Attachment")[0].gsub(/<\/?[^>]*>/, "")
    end
  end
  q = @dbh.prepare("select username from camphone_users where identifier = ? and password = ? limit 1")
  username = nil
  passwords.each do |candidate|
    log "Firing db lookup for password: #{candidate}"
    break if username = q.execute(mms.number, candidate).fetch
  end
  if username.nil?
    log "Username not found! Identifier: #{mms.number}, password: #{passwords.join(',')}." and exit end
  username.to_s.downcase
end

def send_mail(email, subject)
  reply = email.create_reply
  reply.subject = subject
  reply.bcc = @opts.reply_bcc
  reply.from = @opts.reply_from
  reply.mime_version = '1.0'
  reply.set_content_type 'text', 'plain'
  msg = reply.encoded

  smtp = Net::SMTP.new(@opts.smtphost, 25)
  smtp.start {
    smtp.send_mail msg, reply.from, reply.destinations
  }
  log "Sent mail to address #{reply.to} with subject: #{subject}."
end

def find_biggest_image(mms)
  biggest_image = mms.default_media.path rescue nil
  if biggest_image.nil?
    images = []
    mms.media['application/octet-stream'].collect {|x| images << x if x =~ /jpg$|gif$/}  # Search any known hashes for jpg|gif strings.
    sorted_images = images.uniq.sorted_by {|x| File.size(x)} # Sort them by size.
    sorted_images.reverse!  # Put the biggest in front.
    biggest_image = sorted_images[0]  # Our biggest image *should* be the user's. 
    log "Had to brute-force the media bits to find the biggest image."
  end
  biggest_image
end

def find_caption(mms)
  text = ""
  if mms.default_text
    rawtext = IO.readlines(mms.default_text.path).join.split.slice!(1..-1).join(" ")  # Remove first word -- their password.
  end
  text = rawtext.slice(2..-1) if rawtext =~ /^qq/  # If 'qq...' exists, we've got a caption.
  text = text.split("qq")[0] unless text.nil?  # Let's allow qq delimiter on both sides of the caption.
  log "Finished text search; text: #{text}" if text
  text
end  


def upload_image(username, image, text)
  agent = Mechanize.new
  agent.cookie_jar.load(@opts.cookie)
  page = agent.get(@opts.upload_to)
  form = page.forms[0]
  form.multiple = username.downcase
  form.file_uploads.first.file_name = image
  page = form.submit
  uploaded = page.search(@opts.uploaded_xpath).inner_html
  if !uploaded.empty?
    log "Got link from uploader: #{uploaded}."
  else
    log "Upload failed."
    exit
  end
  message = "#{uploaded}"
  message << "<br/><br/>" + text unless text.nil?
  message
end

def do_forum_post(username, message)
  q = @dbh.prepare("insert into posts (fid, tid, author, message, dateline) values (?,?,?,?,?)")
  if q.execute(@opts.forum_id, @opts.thread_id, username, message, Time.now.to_i.to_s)
    log "Executed post insert."
  else
    log "Error inserting post. Username: #{username}, message: #{message}"
  end
end


# Accept fetchmail's output on STDIN.
incoming = ""
while line = $stdin.gets do
  incoming << line
end

email = TMail::Mail.parse(incoming)
log "----------------"
log "Received email from #{email.from}."
mms = MMS2R::Media.new(email)

@dbh = Mysql.real_connect(@opts.dbhost, @opts.dbuser, @opts.dbpass, @opts.db)

# Main. Are we dealing with a registration, or a picture mail?
if email.subject.strip =~ /^reg/i
  log "Email had a subject of /reg*/, so we're dealing with a registration."
  handle_registrations(mms, email)
else
  log "Looks like a picture mail."
  begin
    username = find_username(mms)
    biggest_image = find_biggest_image(mms)
    text = find_caption(mms)
    message = upload_image(username, biggest_image, text)
    
    mms.purge  # Delete tempfiles.

    do_forum_post(username, message)
  rescue Exception => e
    log e.message
    log e.backtrace.inspect
  end
end
