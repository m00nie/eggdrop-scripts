#########################################################################################
# Name                  m00nie::weather
# Description           Uses wunderground API to grab some weather...
#
# 			Requires channel to be flagged with +weather
#
# 			Commands:
# 			!wl <format> <location>
# 				<format> can be 0 for Metric, 1 for Imperial or 2 for both
# 			!w <location>
# 				Grabs current weather in location. If no location is suuplied will try to use users
# 				saved location
# 			!wf <forecast>
# 				Same as !w but provides a 3 day forecast
#
# Version               2.1 - Adds sunrise/sunset info (controlled by variable as requires additional API call)
#                       2.0 - Add option below to automagically add forecast for next 3 hours to each current weather
#                             	request
#                       1.8 - Trying to improve code around mask/nick changes...
#                       1.7 - Users can now set their own prefered metric type (Defaults to global forc variable type for
#                       users that dont have metric type defined).
#                       1.6 - Corrects wind conditions when set to Metric, or Combined
#                             	Adjusted styling for better readability (Contibuted by random4t4x14)
#                       1.5 - Corrects flag detection for chans and adds option for current conditions to display
#                             	both F and C temps in the same output. Might add this to forecast in future version
#                       1.4 - Warn on more than 5 possible restults (stops LOTS of spam)
#                       1.3 - Added warning when mutlple/unclear matches
#                       1.2 - Correct RFC compliant output for some IRCDs (thanks to Alan and Robert for highlighting)
#                       1.1 - F/C tempreture option
#                       1.0 - Initial Release
#
# Website               https://www.m00nie.com
# Notes                 Grab your own key @ http://www.wunderground.com/weather/api
#########################################################################################
namespace eval m00nie {
	namespace eval weather {
		package require http
		package require tdom
		bind pub - !w m00nie::weather::current_call
		bind pub - !wl m00nie::weather::location
		bind pub - !wf m00nie::weather::forecast_call
		variable version "2.1"
		# Set forc to 0 for tempreture in Celsius, 1 for Farenheit or 2 for both!
		# At the moment forecasts can only use 0 or 1, 2 will default back to Celsius
		variable forc "2"
		# Set below to 1 to add hourly info for the next few hours to each current weather report
		# (note this adds an extra API call to each query so on a busy chan you may it API limits)
		variable hourinf "1"
		# Set below to 1 to add sunrise/sunset info to each current weather report
		# (note this adds an extra API call to each query so on a busy chan you may it API limits)
		variable suninf "1"
		setudef flag weather
		variable key "--GET-YOUR-OWN--"
		::http::config -useragent "Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:49.0) Gecko/20100101 Firefox/49.0"

proc current_call {nick uhost hand chan text} {
	set location [verify $hand $chan $text]
	if {$location != 0} {
		set forc [metricpref $hand]
		current $forc $location $chan
	}
}

proc forecast_call {nick uhost hand chan text} {
	set location [verify $hand $chan $text]
	if {$location != 0} {
		set forc [metricpref $hand]
		forecast $forc $location $chan
	}
}

# Allow a user to save their location so they can search without defining it each time
proc location {nick uhost hand chan text} {
	putlog "nick: $nick, uhost: $uhost, hand: $hand"
	set forc [string index $text 0]
	set text [string range $text 2 end]

	if {!(($forc == 0) || ($forc == 1) || ($forc == 2)) } {
		puthelp "PRIVMSG $chan :Output units must be specified from 0-2 where 0 = metric, 1 = imperial and 2 = both. E.g \"!wl 2 London Uk\" would spam both unit types for London."
		return
	}
	if { [string length $text] <= 0 } {
		puthelp "PRIVMSG $chan :Your location seemed very short? :("
	}
	if {![validuser $hand]} {
		adduser $nick
		set mask [maskhost [getchanhost $nick $chan]]
		setuser $nick HOSTS $mask
		chattr $nick -hp
		putlog "m00nie::weather::location added user $nick with host $mask"
	}
	setuser $hand XTRA m00nie:weather.location $text
	setuser $hand XTRA m00nie:weather.forc $forc
	if { $forc == 0 } {
		set unit "metric"
	} elseif { $forc == 1 } {
		set unit "imperial"
	} elseif { $forc == 2 } {
		set unit "both imperial & metric"
	}
	puthelp "PRIVMSG $chan :Default weather location for \002$nick\002 set to \002$text\002 and output units set to \002$unit\002"
	putlog "m00nie::weather::location $nick set their default location to $text."
}

proc metricpref {hand} {
	set forc [getuser $hand XTRA m00nie:weather.forc]
	if {!(($forc == 0) || ($forc == 1) || ($forc == 2)) } {
		set forc $m00nie::weather::forc
	}
	return $forc
}

# Search for current weather
 proc verify {hand chan text} {
	if {(![channel get $chan weather])} {
		putlog "m00nie::weather::search Trigger seen but channel doesnt have +weather set!"
		return 0
	}
	if {$text != ""} {
		set location $text
	} else {
		set location [getuser $hand XTRA m00nie:weather.location]
	}
	if {[string length $location] == 0 || [regexp {[^0-9a-zA-Z,. ]} $location match] == 1} {
		putlog "m00nie::weather::search location b0rked or no location said/default? Argument: $location"
		puthelp "PRIVMSG $chan :Did you ask to search somewhere? Or use !wl to set a default location"
	return
	} else {
		return $location
	}
}

 proc current {forc location chan} {
	putlog "m00nie::weather::current is running against location: $location and metric pref of $forc"
	set rawpage [getinfo $location conditions]
	set doc [dom parse $rawpage]
	set root [$doc documentElement]
	# Check for no results!
	set notfound [$root selectNodes /response/error/description/text()]
	if {[llength $notfound] > 0 } {
		set errormsg [$notfound nodeValue]
		putlog "m00nie::weather::current ran but could not find any info for $location or an API error occured: $errormsg"
		puthelp "PRIVMSG $chan :$errormsg"
		return
	}
	# Check for multiple results
	set multi [$root selectNodes /response/results/result]
	if {[llength $multi]} {
		putlog "m00nie::weather::current multiple results found"
		# Lets check we dont have LOADS of results to spam
		set i 0
		foreach place [$root selectNodes "/response/results/result"] {
			incr i
			if {$i >= 5} {
				puthelp "PRIVMSG $chan :Your search returned more than 5 results. Please try a more specific search."
				return
			}
		}
		puthelp "PRIVMSG $chan :Multiple results found pick one and run again"
		foreach place [$root selectNodes "/response/results/result"] {
			set name [lindex [$place selectNodes "name"] 0]
			set country [lindex [$place selectNodes "country"] 0]
			if {[$country text] eq "US"} {
				set state [lindex [$place selectNodes "state"] 0]
				puthelp "PRIVMSG $chan : - [$name text] [$state text] [$country text]"
			} else {
				puthelp "PRIVMSG $chan : - [$name text] [$country text]"
			}
		}
		return
	}
	set city [[$root selectNodes /response/current_observation/display_location/full/text()] nodeValue]
	if { $forc == 0 } {
		foreach var { observation_time weather temp_c wind_dir wind_kph wind_gust_kph feelslike_c precip_today_string } {
			set $var [[$root selectNodes /response/current_observation/$var/text()] nodeValue]
		}
		append temp_c "°C"
		append feelslike_c "°C"
		set spam "Current weather for \002$city\002 ($observation_time) \002Current conditions:\002 $weather, \002Temperature:\002 $temp_c, \002Wind:\002 From $wind_dir at $wind_kph KPH Gusting to $wind_gust_kph KPH, \002Rain today:\002 $precip_today_string, \002Feels like:\002 $feelslike_c"
	} elseif { $forc == 1} {
		foreach var { observation_time weather temp_f wind_string feelslike_f precip_today_string } {
			set $var [[$root selectNodes /response/current_observation/$var/text()] nodeValue]
		}
		append temp_f "F"
		append feelslike_f "F"
		set spam "Current weather for \002$city\002 ($observation_time) \002Current conditions:\002 $weather, \002Temperature:\002 $temp_f, \002Wind:\002 $wind_string, \002Rain today:\002 $precip_today_string, \002Feels like:\002 $feelslike_f"
	} elseif { $forc == 2} {
		foreach var { observation_time weather temp_f temp_c wind_dir wind_mph wind_kph wind_gust_mph wind_gust_kph feelslike_string precip_today_string } {
			set $var [[$root selectNodes /response/current_observation/$var/text()] nodeValue]
		}
		append temp_f "F"
		append temp_c "°C"
		set spam "Current weather for \002$city\002 ($observation_time) \002Current conditions:\002 $weather, \002Temperature:\002 $temp_f ($temp_c), \002Wind:\002 From the $wind_dir at $wind_mph MPH ($wind_kph KPH) Gusting to $wind_gust_mph MPH ($wind_gust_kph KPH), \002Rain today:\002 $precip_today_string, \002Feels like:\002 $feelslike_string"
	} else {
		putlog "m00nie::weather::current $forc is not a valid value for forc..."
		return
	}
	if { $m00nie::weather::hourinf == 1 } {
		set rawpage [getinfo $location hourly]
        	set doc [dom parse $rawpage]
        	set root [$doc documentElement]
        	# Check for no results!
       	 	set notfound [$root selectNodes /response/error/description/text()]
        	if {[llength $notfound] > 0 } {
        		set errormsg [$notfound nodeValue]
        		putlog "m00nie::weather::current ran but could not find any info for $location or an API error occured: $errormsg"
        		puthelp "PRIVMSG $chan :$errormsg"
        		return
        	}
		append spam " \002Three hour forecast:\002 "
		set i 0
		foreach hour [$root selectNodes "/response/hourly_forecast/forecast"] {
                        incr i
                        if {$i >= 4} {
                                break
                        }
                       	set civ [[$hour selectNodes "FCTTIME/civil/text()"] nodeValue]
			set cond [[$hour selectNodes "condition/text()"] nodeValue]
			if { $i == 1 } {
                                append spam $civ
                        } else {
                        	append spam ", " $civ
                        }
			append spam { } $cond
			if { $forc == 0 } {
				set temp [[$hour selectNodes "temp/metric/text()"] nodeValue]
				append temp "°C"
				append spam { } $temp
			} elseif { $forc == 1} {
				set temp [[$hour selectNodes "temp/english/text()"] nodeValue]
				append temp "F"
                                append spam { } $temp
			} else {
				set temp_c [[$hour selectNodes "temp/metric/text()"] nodeValue]
				set temp_f [[$hour selectNodes "temp/english/text()"] nodeValue]
				append temp_c "°C"
				append temp_f "F"
				set temp "$temp_f ($temp_c)"
                                append spam { } $temp
			}
                }
	}
	if { $m00nie::weather::suninf == 1 } {
		set rawpage [getinfo $location astronomy]
		set doc [dom parse $rawpage]
		set root [$doc documentElement]
		# Check for no results!
		set notfound [$root selectNodes /response/error/description/text()]
		if {[llength $notfound] > 0 } {
			set errormsg [$notfound nodeValue]
			putlog "m00nie::weather::current ran but could not find any info for $location or an API error occured: $errormsg"
			puthelp "PRIVMSG $chan :$errormsg"
			return
		}
		set sunsh [[$root selectNodes /response/sun_phase/sunset/hour/text()] nodeValue]
		set sunsm [[$root selectNodes /response/sun_phase/sunset/minute/text()] nodeValue]
		set sunrh [[$root selectNodes /response/sun_phase/sunrise/hour/text()] nodeValue]
		set sunrm [[$root selectNodes /response/sun_phase/sunrise/minute/text()] nodeValue]
		set sunspam "\002Sunrise\002 $sunrh:$sunrm, \002Sunset\002 $sunsh:$sunsm"
		append spam { } $sunspam
  }
	puthelp "PRIVMSG $chan :$spam"
}

proc forecast {forc location chan} {
	putlog "m00nie::weather::forecast is running against location: $location"
	set rawpage [getinfo $location forecast]
	set doc [dom parse $rawpage]
	set root [$doc documentElement]
	set dayList [$root selectNodes /response/forecast/txt_forecast/forecastdays/forecastday/title/text()]
	if { ($forc == 0) || ($forc == 2) } {
		set foreList [$root selectNodes /response/forecast/txt_forecast/forecastdays/forecastday/fcttext_metric/text()]
	} elseif { $forc == 1 } {
		set foreList [$root selectNodes /response/forecast/txt_forecast/forecastdays/forecastday/fcttext/text()]
	} else {
		putlog "m00nie::weather::forecast $forc is not a valid value for forc..."
		return
	}
	puthelp "PRIVMSG $chan :Three day forecast for \002$location\002"
	set x 0
	while { $x < 6 } {
		set dayname [[lindex $dayList $x] nodeValue]
		set fore [[lindex $foreList $x] nodeValue]
		puthelp "PRIVMSG $chan :\002$dayname:\002 $fore"
		incr x
	}
}

proc getinfo {location type} {
	regsub -all -- { } $location {%20} location
	set url "http://api.wunderground.com/api/$m00nie::weather::key/$type/q/$location.xml"
	putlog "m00nie::weather::getinfo grabbing data from $url"
	for { set i 1 } { $i <= 5 } { incr i } {
		set xmlpage [::http::data [::http::geturl "$url" -timeout 10000]]
		if {[string length xmlpage] > 0} { break }
	}
	putlog "m00nie::weather::getinfo xmlpage length is: [string length $xmlpage]"
	if { [string length $xmlpage] == 0 }  {
		error "wunderground returned ZERO no data :( or we couldnt connect properly"
	}
	return $xmlpage
}
}
}
putlog "m00nie::weather $m00nie::weather::version loaded"
