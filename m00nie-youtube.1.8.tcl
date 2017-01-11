#########################################################################################
# Name			m00nie::youtube
# Description		Uses youtube v3 API to search and return videos
# 	
# Version		1.8 - Chanset +youtube now controls search access!
# 			1.7 - Modify SSL params (fixes issues on some systems)
# 			1.6 - Small correction to "stream" categorisation.....
# 			1.5 - Added UTF-8 support thanks to CatboxParadox (Requires eggdrop
# 				to be compiled with UTF-8 support)
# 			1.4 - Correct time format and live streams gaming etc
#           		1.3 - Updated output to be RFC compliant for some IRCDs
# 			1.2 - Added auto info grabber for spammed links
#			1.1 - Fixing regex!
#			1.0 - Initial release
# Website		https://www.m00nie.com
# Notes			Grab your own key @ https://developers.google.com/youtube/v3/
#########################################################################################
namespace eval m00nie {
   namespace eval youtube {
	package require http
	package require json
	package require tls
        tls::init -tls1 true -ssl2 false -ssl3 false
	http::register https 443 tls::socket
	bind pub - !yt m00nie::youtube::search
	bind pubm - * m00nie::youtube::autoinfo
	variable version "1.8"
	setudef flag youtube
	variable key "GET-YOUR-OWN"
	variable regex {(?:http(?:s|).{3}|)(?:www.|)(?:youtube.com\/watch\?.*v=|youtu.be\/)([\w-]{11})}
	::http::config -useragent "Mozilla/5.0 (X11; Linux x86_64; rv:29.0) Gecko/20100101 Firefox/29.0"

proc autoinfo {nick uhost hand chan text} {
	if {[channel get $chan youtube] && [regexp -nocase -- $m00nie::youtube::regex $text url id]} {
		putlog "m00nie::youtube::autoinfo is running"
		putlog "m00nie::youtube::autoinfo url is: $url and id is: $id"
		set url "https://www.googleapis.com/youtube/v3/videos?id=$id&key=$m00nie::youtube::key&part=snippet,statistics,contentDetails&fields=items(snippet(title,channelTitle,publishedAt),statistics(viewCount),contentDetails(duration))"
		set ids [getinfo $url]
		set title [encoding convertfrom [lindex $ids 0 1 3]]
		set pubiso [lindex $ids 0 1 1]
		regsub {\.000Z} $pubiso "" pubiso
		set pubtime [clock format [clock scan $pubiso]]
		set user [encoding convertfrom [lindex $ids 0 1 5]]
		# Yes all quite horrible...
		set isotime [lindex $ids 0 3 1]
		regsub -all {PT|S} $isotime "" isotime
                regsub -all {H|M} $isotime ":" isotime
		if { [string index $isotime end-1] == ":" } {
			set sec [string index $isotime end]
                        set trim [string range $isotime 0 end-1]
                        set isotime ${trim}0$sec
		} elseif { [string index $isotime 0] == "0" } {
			set isotime "stream"
		} elseif { [string index $isotime end-2] != ":" } {
			set isotime "${isotime}s"
		}
		set views [lindex $ids 0 5 1]
		puthelp "PRIVMSG $chan :\002\00301,00You\00300,04Tube\003\002 \002$title\002 by $user (duration: $isotime) on $pubtime, $views views"

	}
}

proc getinfo { url } {
	for { set i 1 } { $i <= 5 } { incr i } {
        	set rawpage [::http::data [::http::geturl "$url" -timeout 5000]]
        	if {[string length rawpage] > 0} { break }
        }
        putlog "m00nie::youtube::getinfo Rawpage length is: [string length $rawpage]"
        if {[string length $rawpage] == 0} { error "youtube returned ZERO no data :( or we couldnt connect properly" }
        set ids [dict get [json::json2dict $rawpage] items]
	putlog "m00nie::youtube::getinfo IDS are $ids"
	return $ids

}

proc search {nick uhost hand chan text} {
        if {![channel get $chan youtube] } {
                return
        }
	putlog "m00nie::youtube::search is running"
	regsub -all {\s+} $text "%20" text
	set url "https://www.googleapis.com/youtube/v3/search?part=snippet&fields=items(id(videoId),snippet(title))&key=$m00nie::youtube::key&q=$text"
	set ids [getinfo $url]
	set output "\002\00301,00You\00300,04Tube\003\002 "
	for {set i 0} {$i < 5} {incr i} {
		set id [lindex $ids $i 1 1]
		set desc [encoding convertfrom [lindex $ids $i 3 1]]
		set yout "https://youtu.be/$id"
		append output "\002" $desc "\002 - " $yout " | "
	}
	set output [string range $output 0 end-2]
	puthelp "PRIVMSG $chan :$output"
}
}
}
putlog "m00nie::youtube $m00nie::youtube::version loaded"
