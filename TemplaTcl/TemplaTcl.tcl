#!/usr/bin/tclsh
#
# TemplaTcl: a Tcl template engine
# Created by Federico Ferri (FF) at Tcler's Wiki.
#     https://wiki.tcl.tk/18175
#
# The engine works by converting a template (which is a string, or a file)
# into a Tcl script, and then running it. Nearly each line of text encountered
# will be returned as is. The exception is text between <% ... %> which is
# treated as Tcl code.
#
# Add cacheFile and parseCache by Danilo Chang.
# Known issue: Do not work at Tcl 8.6.1.
#

package require Tcl 8.5
# 8.5 required cause the {*} in proc create and proc method
package require struct
# tcllib required

package provide TemplaTcl 0.1

namespace eval ::TemplaTcl {
    variable obj

    proc method {name args body} {
        proc $name [list self {*}$args] "variable obj ; $body"
    }

    method create {} {
        # create and setup a safe interpreter
        # for running template's tcl code
        catch {if [interp exists $obj($self:interp)] {
                interp delete $obj($self:interp)}}
        set obj($self:interp) [interp create -safe]
        interp share {} stdout $obj($self:interp)
        interp eval $obj($self:interp) {
            proc _defaultSpool {txt {cmd {}}} {
                global content
                if {$cmd == "clear"} {
                    set content {};
                    return
                } elseif {$cmd == "get"} {
                    return $content
                } else {
                    append content $txt
                }
            }
        }
        # Add by Danilo Chang, using a dict to store our data
        set obj($self:dictcache) [dict create]
        uplevel "proc $self {method args} {namespace eval ::TemplaTcl \[list \$method $self {*}\$args\]}"
        return $self
    }

    method cacheFile {filename} {
        if {[catch {set fh [open $filename r]}]==1} {
             return -core error "Open fail"
        }
        set raw [read $fh]
        close $fh

        dict set obj($self:dictcache) $filename $raw
    }

    method parseCache {filename} {
        if {[dict exists $obj($self:dictcache) $filename]==1} {
            set raw [dict get $obj($self:dictcache) $filename]
        } else {
            if {[catch {set fh [open $filename r]}]==1} {
                return -core error "Open fail"
            }
            set raw [read $fh]
            close $fh

            dict set obj($self:dictcache) $filename $raw
        }
        return [$self parse $raw]
    }

    method parseFile {filename} {
        # read the template into $rawl - list of chars
        if {[catch {set fh [open $filename r]}]==1} {
            return -core error "Open fail"
        }
        set raw [read $fh]
        close $fh

        return [$self parse $raw]
    }

    method parse {template} {
        $self _setMode raw
        #$self setOption printCommand "puts -nonewline"
        $self setOption printCommand "_defaultSpool"
        $self setVar * {}
        set q [::struct::queue]
        set rawl [split $template {}]
        foreach ch $rawl {
            # we work char-by-char :|
            $q put $ch
            # max block to compare (<%=) is 3 chars long:
            if {[$q size] >= 3} {
                set s3 [join [$q peek 3] {}]
                set s2 [join [$q peek 2] {}]
                switch $obj($self:mode) {
                    raw {
                        if {$s3 == "<%="} {
                            # <%= is a shorthand for puts ...
                            $q get 3; $self _setMode code;
                            append obj($self:buf:$obj($self:mode)) "$obj($self:options:printCommand) "
                            continue
                        } elseif {$s3 == "<%@"} {
                            # <%@ is for setting preprocessor options
                            $q get 3; $self _setMode opt; continue
                        } elseif {$s2 == "<%"} {
                            # <% indicates begin of a code block
                            $q get 2; $self _setMode code; continue
                        }
                    }
                    code {
                        if {$s2 == "%>"} {
                            # and %> is the end of code block
                            $q get 2; $self _setMode raw; continue
                        }
                    }
                    opt {
                        if {$s2 == "%>"} {
                            # option parser
                            $q get 2;
                            $self _parseOptions $obj($self:buf:opt)
                            set obj($self:buf:opt) {}
                            $self _setMode raw; continue
                        }
                    }
                }
                append obj($self:buf:$obj($self:mode)) [$q get]
            }
        }
        # finish processing the queue:
        while {[$q size] > 0} {
            append obj($self:buf:$obj($self:mode)) [$q get]
        }
        $self _setMode flush
        # cleanup:
        foreach v {buf:code buf:opt buf:raw mode modeprev} {catch {unset obj($self:$v)}}
    }

    method render {} {
        # run the template script
        set tclBuf ""
        foreach l $obj($self:data) {
            set t [lindex $l 0]
            set d [lindex $l 1]
            switch $t {
                raw {
                    append tclBuf "$obj($self:options:printCommand) [list $d]\n"
                }
                code {
                    append tclBuf "$d\n"
                }
            }
        }
        foreach {var val} $obj($self:variables) {$obj($self:interp) eval [list set $var $val]}
        #puts $tclBuf;return
        if {$obj($self:options:printCommand) == "_defaultSpool"} {
            $obj($self:interp) eval {_defaultSpool {} clear}
        }
        $obj($self:interp) eval $tclBuf
        if {$obj($self:options:printCommand) == "_defaultSpool"} {
            set x [$obj($self:interp) eval {_defaultSpool {} get}]
            $obj($self:interp) eval {_defaultSpool {} clear}

            # Danilo Chang: try to clean data after render
            set obj($self:data) {}
            return $x
        }
    }

    method setOption {opt value} {
        switch $opt {
            printCommand {set obj($self:options:$opt) $value}
            include {
                set o inc$value
                create $o
                $o parseFile $value
                set prevMode [$self _setMode raw]
                append obj($self:buf:raw) [$o render]
                $self _setMode $prevMode
            }
            source {$obj($self:interp) invokehidden source $value}
            default {return -code error -errorinfo "Unknown option: $opt"}
        }
    }

    method setVar {var value} {
        if {$var == "*" && $value == ""} {
            set obj($self:variables) {};
            return
        }
        lappend obj($self:variables) $var
        lappend obj($self:variables) $value
    }

    method _setMode {m} {
        set modenew {}
        switch $m {code - raw - opt {set modenew $m}}
        if {$modenew != {}} {
            if [catch {set obj($self:mode)}] {set obj($self:mode) $modenew}
            set obj($self:modeprev) $obj($self:mode)
            set obj($self:mode) $modenew
            set obj($self:buf:$obj($self:mode)) {}
            if {$obj($self:modeprev) == {}} {
                    set obj($self:modeprev) $obj($self:mode)
            }
        }
        if {$m == "flush"} {
            set obj($self:modeprev) $obj($self:mode)
            set obj($self:mode) _
        }
        if {$obj($self:mode) != $obj($self:modeprev)} {
            lappend obj($self:data) [list $obj($self:modeprev) $obj($self:buf:$obj($self:modeprev))]
            set obj($self:buf:$obj($self:modeprev)) {}
            return $obj($self:modeprev)
        }
    }

    method _parseOptions {o} {
        set optlist [split $o "\n;"]
        foreach opt $optlist {
            set pair [split $opt =]
            set opt_ [string trim [lindex $pair 0]]
            if {$opt_ == {}} continue
            $self setOption $opt_ [string trim [lindex $pair 1]]
        }
    }
}

