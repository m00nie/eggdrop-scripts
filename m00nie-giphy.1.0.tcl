#########################################################################################
# Name			m00nie::giphy
# Description		Uses giphy API to search and return images
# 	
# Version		1.0 - Initial release
# Website		https://www.m00nie.com
# Notes			API key is open/shared!
# 			.chanset #blah +giphy
#########################################################################################
namespace eval m00nie {
   namespace eval giphy {
	package require http
	package require json
	bind pub - !gif m00nie::giphy::search
	variable version "1.0"
	setudef flag giphy	
	# At least for the moment this is a common key for everyone
	variable key "dc6zaTOxFJmzC"
	::http::config -useragent "Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:48.0) Gecko/20100101 Firefox/48.0"


proc getinfo { url } {
	for { set i 1 } { $i <= 5 } { incr i } {
        	set rawpage [::http::data [::http::geturl "$url" -timeout 5000]]
        	if {[string length rawpage] > 0} { break }
        }
        putlog "m00nie::giphy::getinfo Rawpage length is: [string length $rawpage]"
        if {[string length $rawpage] == 0} { error "giphy returned ZERO no data :( or we couldnt connect properly" }
        set ids [dict get [json::json2dict $rawpage] data]
	putlog "m00nie::giphy::getinfo IDS are $ids"
	return $ids

}

proc search {nick uhost hand chan text} {
        if {![channel get $chan giphy] } {
                return
        }
	putlog "m00nie::giphy::search is running"
	regsub -all {\s+} $text "%20" text
	set url "http://api.giphy.com/v1/gifs/search?q=$text&api_key=$m00nie::giphy::key"
	set ids [getinfo $url]
	set output "\002\00300,01GIPHY\003\002 "
	for {set i 0} {$i < 5} {incr i} {
		set id [lindex $ids $i 9]
		putlog "RESULT: $id"
		if {([string length $id] == 0) && ($i == 0) } {
			append output "No results found | "
			break
		} elseif {[string length $id] == 0} {
			break
		} else {			
			append output "$id | "
		}
	}
	set output [string range $output 0 end-2]
	puthelp "PRIVMSG $chan :$output"
}
}
}
putlog "m00nie:::giphy $m00nie::giphy::version loaded"
