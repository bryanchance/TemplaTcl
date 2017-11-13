#!/usr/bin/tclsh

package require tanzer
package require tanzer::file::handler
package require TemplaTcl

set server [::tanzer::server new]

TemplaTcl::create template
template cacheFile index.tmpl
template cacheFile about.tmpl

set root "."

$server route GET {/} {.*:8080} apply {
	{event session args} {
		if {$event ne "write"} {
			return
		}

		$session response -new [::tanzer::response new 200 {
			Content-Type "text/html"
		}]

		template parseCache index.tmpl
		$session response buffer [template render]
		$session respond
		$session nextRequest
	}
}

$server route GET /about {.*:8080} apply {
	{event session args} {
		if {$event ne "write"} {
			return
		}

		$session response -new [::tanzer::response new 200 {
			Content-Type "text/html"
		}]
		
		template parseCache about.tmpl
		template setVar cityList {Taipei {Hong Kong} Tokyo {New York} London}
		$session response buffer [template render]
		$session respond
		$session nextRequest
	}
}

$server route {.*} /* {.*} [::tanzer::file::handler new [list \
	root     $root \
	listings 1 \
]]

$server listen 8080
