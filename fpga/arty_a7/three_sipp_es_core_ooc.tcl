# =============================================================================
# three_sipp_es_core_ooc.tcl — Vivado batch flow for Out-Of-Context three_sipp_es_core
# =============================================================================
set fpga_dir  [file normalize [file dirname [info script]]]
set build_dir [expr {[llength $argv] >= 1 ? [lindex $argv 0] : "$fpga_dir/build_ooc"}]
set is_secure [expr {[llength $argv] >= 2 ? [lindex $argv 1] : 0}]
set part      xc7a100tcsg324-1

file mkdir $build_dir
cd $build_dir

set fp [open $fpga_dir/three_sipp_es_arty_a7.f r]
while {[gets $fp line] >= 0} {
  set line [string trim $line]
  if {$line eq "" || [string match "#*" $line] || [string match "//*" $line]} { continue }
  if {[string match "+incdir+*" $line]} {
    set incdir [string range $line 8 end]
    set_property include_dirs [list [file normalize "$fpga_dir/$incdir"]] [current_fileset]
    continue
  }
  read_verilog -sv [file normalize $fpga_dir/$line]
}
close $fp

set_property part $part [current_project]
set_property top three_sipp_es_core [current_fileset]

# OOC constraints (target 100 MHz / 10.0 ns)
set xdc_file [open "ooc.xdc" w]
puts $xdc_file "create_clock -period 10.0 -name clk \[get_ports clk\]"
close $xdc_file
read_xdc -mode out_of_context "ooc.xdc"

if {$is_secure} {
    synth_design -top three_sipp_es_core -part $part -mode out_of_context -generic SECURE=1 -directive PerformanceOptimized
} else {
    synth_design -top three_sipp_es_core -part $part -mode out_of_context -directive PerformanceOptimized
}

opt_design -directive Explore
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore

report_utilization -hierarchical -file util_hier.rpt
report_utilization -file util.rpt
report_timing_summary -file timing.rpt

puts "DONE OOC BUILD"
