#########################################################################################
# Name			m00nie::news
# Description		Uses newsapi.org to find some recent new for various sites. Also allows
#               users to specify their own default news site thats checked for them
#
# Version		1.0 - Initial release
# Website		https://www.m00nie.com
# Notes			Grab your own key @ https://newsapi.org/register
#########################################################################################
namespace eval m00nie {
   namespace eval news {
	package require http
	package require json
	package require tls
        tls::init -tls1 true -ssl2 false -ssl3 false
	http::register https 443 tls::socket
	bind pub - !news m00nie::news::search
  bind pub - !setnews m00nie::news::source
	variable version "1.0"
	setudef flag news
	variable key "GET-YOUR-OWN"
	::http::config -useragent "Mozilla/5.0 (X11; Fedora; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

  # Allow a user to save their choice of news source
  proc source {nick uhost hand chan text} {
      putlog "m00nie::news::source nick: $nick, uhost: $uhost, hand: $hand"
      if { [string length $text] <= 0 } {
          puthelp "PRIVMSG $chan :Your source name seemed very short? Pick one from https://newsapi.org/sources"
          return
      }
      set url "https://newsapi.org/v1/sources?&apiKey=$m00nie::news::key"
      set ids [getinfo $url]
      set ids [lindex $ids 3]
      set result [lsearch -regexp $ids $text]
      if { $result <= 0 } {
          puthelp "PRIVMSG $chan :Couldn't find source $text. Pick one from https://newsapi.org/sources"
          return
      }

      putlog "RESSULT: $result"
      set spam [lindex $ids $result]
      putlog "Name: [lindex $ids $result 3], Description: [lindex $ids $result 7]"

      if {![validuser $hand]} {
          adduser $nick
          set mask [maskhost [getchanhost $nick $chan]]
          setuser $nick HOSTS $mask
          chattr $nick -hp
          putlog "m00nie::news::source added user $nick with host $mask"
      }
      setuser $hand XTRA m00nie:news.source $text
      setuser $hand XTRA m00nie:news.name [lindex $ids $result 3]
      puthelp "PRIVMSG $chan :set default source to [lindex $ids $result 3]([lindex $ids $result 1]) - [lindex $ids $result 7]"
      putlog "m00nie::news::source $nick set their default source to $text."
  }

proc getinfo { url } {
	for { set i 1 } { $i <= 5 } { incr i } {
        	set rawpage [::http::data [::http::geturl "$url" -timeout 5000]]
        	if {[string length rawpage] > 0} { break }
        }
        putlog "m00nie::news::getinfo Rawpage length is: [string length $rawpage]"
        if {[string length $rawpage] == 0} { error "newsapi returned ZERO no data :( or we couldnt connect properly" }
        set ids [dict get [json::json2dict $rawpage]]
	return $ids

}

proc search {nick uhost hand chan text} {
        if {![channel get $chan news] } {
                return
        }
	putlog "m00nie::news::search is running"
	set source [getuser $hand XTRA m00nie:news.source]
  set name [getuser $hand XTRA m00nie:news.name]
  if {([string length $source] <= 0) || ([string length $name] <= 0) } {
      puthelp "PRIVMSG $chan :No default news source found for you. Please set one using !setnews"
      return
  }
  putlog "Grabbing news for $nick, with source of $source and name of $name"
	set url "https://newsapi.org/v1/articles?source=$source&sortBy=latest&apiKey=$m00nie::news::key"
	set ids [getinfo $url]
	for {set i 0} {$i < 3} {incr i} {
    set title [encoding convertfrom [lindex $ids 7 $i 3]]
		set url [lindex $ids 7 $i 7]
    if { $i == 0 } {
		    set output "$name: \002$title\002 - $url"
    } else {
        set output "\002$title\002 - $url"
    }
    puthelp "PRIVMSG $chan :$output"
	}
}
}
}
putlog "m00nie::news $m00nie::news::version loaded"
