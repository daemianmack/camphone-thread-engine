What's this thing?
=================

This script...

- harvests user-generated pictures out of camphone emails,
- posts them to an upload utility, and 
- cross-posts the resulting URL to a webforum, masquerading as the authenticated user, and finally,
- allows users to register with the service so they can do the above.

It'd be trivial to replace bulletpoint 2 with 'sends them off to a mailing list/flickr/Facebook' or replace bulletpoint 3 with 'posts the URL to my blog/tumblog/digital pictureframe/Times Square bulletin board', etc.

Mail comes in via fetchmail/procmail or whatever your favorite mail-handling system might be. I've included the fetchmail config for completeness.


This script will accept two flavors of email:
--------------------------------------------

1. **Registration** email. 

        Subj: register
        Body: [USERNAME] [PASSWORD]

    If this script finds a subject starting with the string 'reg', it will create an entry in a DB table ('camphone_user') using the first word of the email body as the username and the second word as the password. It will also use the sender address as an identifier. (Depending on carrier, this may be the phone number, or it may be the human-friendly From: field of the sending email client. In either case, it serves to distinguish the sending device.)

    After registering a user, the script will reply to their email address with a confirmation.



2. **Camphone** email. 

        Subj: N/A
        Body: [PASSWORD] qq[SOME TEXT]qq

    If this script does not find a subject starting with 'reg', and instead finds an image attached, it will parse the email for a password, the identifying string, and optionally a caption bookended in double Qs.

    That is, the first word in the body of the email must be the password stored previously for the user via their registration email. Optionally, they can add a text caption to the photo that will be added to the forum post. I've chosen 'qq' as a sentinel since it's a rare sequence. This way we clearly delineate password from caption and other text, which carriers will tack on without regard for our sanity. Users whose emails must contain disclaimers and such can use the optional 'qq' sentinel at the *end* of their caption as well, to bookend it.



### Also

Enclosed please find two sample mailfiles, one for each flavor of email. You can use these to test your own setup, format changes, etc.

Note that you'll need Github's version of MMS2R...

    sudo gem sources -a http://gems.github.com
    sudo gem install monde-mms2r

as the version available via the vanilla gem sources causes TMail to emit errors regarding 'return_path' or 'with_indifferent_access' being undefined methods.


MySQL schema of camphone_users...

    CREATE TABLE `camphone_users` (
      `username` varchar(25) NOT NULL,
      `identifier` varchar(255) NOT NULL,
      `password` varchar(50) DEFAULT NULL,
      UNIQUE KEY `username` (`username`,`identifier`)
    )


This is all possible thanks to the wondrous MMS2R gem made available by Mike Mondragon, which must represent hours of patience sorting through the aberrant things providers do with, to, and alongside the MMS messages you send through their systems. Startling but true footnote follows: A canadian colleague of mine is on Sasktel. Every single one of his MMSs come through with a little surprise gift from his carrier: the entire contents of an XHTML Basic 1.0 DTD as an inline attachment to his message. It's 1500 lines long and takes up 63k. (I can't figure out whether this would be more preposterous if he were paying by the kilobyte, or on a free data plan.)