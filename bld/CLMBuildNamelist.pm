# build-namelist
#
# This script builds the namelists for CLM
#
# The simplest use of build-namelist is to execute it from the build directory where configure
# was run.  By default it will use the config_cache.xml file that was written by configure to
# determine the build time properties of the executable, and will write the files that contain
# the output namelists in that same directory.  But if multiple runs are to made using the
# same executable, successive invocations of build-namelist will overwrite previously generated
# namelist files.  So generally the best strategy is to invoke build-namelist from the run
# directory and use the -config option to provide the filepath of the config_cache.xml file.
#
#
# Date        Contributor      Modification
# -------------------------------------------------------------------------------------------
# 2009-01-20  Vertenstein      Original version
# 2010-04-27  Kluzek           Add ndep streams capability
# 2011-07-25  Kluzek           Add multiple ensemble's of namelists
# 2012-03-23  Kluzek           Add megan namelist and do checking on it
# 2012-07-01  Kluzek           Add some common CESM namelist options
# 2013-12     Andre            Refactor everything into subroutines
# 2013-12     Muszala          Add Ecosystem Demography functionality
# 2017-08-17  Lague			   Add namelist options for simple land model (MML)
#--------------------------------------------------------------------------------------------

package CLMBuildNamelist;

require 5;

use strict;
#use warnings;
#use diagnostics;

use Cwd qw(getcwd abs_path);
use File::Basename qw(dirname);
use English;
use Getopt::Long;
use IO::File;
use File::Glob ':glob';

#-------------------------------------------------------------------------------
#
# Define a small number of global variables
#
#-------------------------------------------------------------------------------

(my $ProgName = $0) =~ s!(.*)/!!;      # name of this script
my $ProgDir  = $1;
$ProgName = "CLM " . "$ProgName";

my $cwd = abs_path(getcwd());  # absolute path of the current working directory
my $log;                       # Log messages object -- will be set in main, declaring it global here means it can be used everywhere

#-------------------------------------------------------------------------------

sub usage {
    die <<EOF;
SYNOPSIS
     build-namelist [options]

     Create the namelist for CLM
REQUIRED OPTIONS
     -cimeroot "directory"    Path to cime directory
     -config "filepath"       Read the given CLM configuration cache file.
                              Default: "config_cache.xml".
     -d "directory"           Directory where output namelist file will be written
                              Default: current working directory.
     -envxml_dir "directory"  Directory name of env_*.xml case files to read in.
                              (if read they allow user_nl_clm and CLM_BLDNML_OPTS to expand
                               variables [for example to use \$DIN_LOC_ROOT])
                              (default current directory)
     -lnd_frac "domainfile"   Land fraction file (the input domain file)
     -res "resolution"        Specify horizontal grid.  Use nlatxnlon for spectral grids;
                              dlatxdlon for fv grids (dlat and dlon are the grid cell size
                              in degrees for latitude and longitude respectively)
                              "-res list" to list valid resolutions.
                              (default: 0.9x1.25)
     -sim_year "year"         Year to simulate for input datasets
                              (i.e. 1850, 2000, 1850-2000, 1850-2100)
                              "-sim_year list" to list valid simulation years
                              (default 2000)
OPTIONS
     -bgc "value"             Build CLM with BGC package [ sp | bgc ]
                              (default is sp).
                                CLM Biogeochemistry mode
                                sp    = Satellite Phenology (SP)
                                    This toggles off the namelist variable: use_cn
                                bgc   = Carbon Nitrogen with methane, nitrification, vertical soil C,
                                        CENTURY decomposition
                                    This toggles on the namelist variables:
                                          use_cn, use_lch4, use_nitrif_denitrif, use_vertsoilc, use_century_decomp
     -[no-]chk_res            Also check [do NOT check] to make sure the resolution and
                              land-mask is valid.
     -clm_demand "list"       List of variables to require on clm namelist besides the usuals.
                              "-clm_demand list" to list valid options.
                              (can include a list member "null" which does nothing)
     -clm_start_type "type"   Start type of simulation
                              (default, cold, arb_ic, startup, continue, or branch)
                              (default=do the default type for this configuration)
                              (cold=always start with arbitrary initial conditions)
                              (arb_ic=start with arbitrary initial conditions if
                               initial conditions do not exist)
                              (startup=ensure that initial conditions are being used)
     -co2_type "value"        Set CO2 the type of CO2 variation to use.
     -co2_ppmv "value"        Set CO2 concentration to use when co2_type is constant (ppmv).
     -csmdata "dir"           Root directory of CESM input data.
                              Can also be set by using the CSMDATA environment variable.
     -glc_nec <name>          Glacier number of elevation classes [0 | 3 | 5 | 10 | 36]
                              (default is 0) (standard option with land-ice model is 10)
     -help [or -h]            Print usage to STDOUT.
     -ignore_ic_date          Ignore the date on the initial condition files
                              when determining what input initial condition file to use.
     -ignore_ic_year          Ignore just the year part of the date on the initial condition files
                              when determining what input initial condition file to use.
     -ignore_warnings         Allow build-namelist to continue, rather than stopping on 
                              warnings
     -infile "filepath"       Specify a file (or list of files) containing namelists to
                              read values from.

                              If used with a CLM build with multiple ensembles (ninst_lnd>1)
                              and the filename entered is a directory to files of the
                              form filepath/filepath and filepath/filepath_\$n where \$n
                              is the ensemble member number. the "filepath/filepath"
                              input namelist file is the master input namelist file
                              that is applied to ALL ensemble members.

                              (by default for CESM this is setup for files of the
                               form \$CASEDIR/user_nl_clm/user_nl_clm_????)
     -inputdata "filepath"    Writes out a list containing pathnames for required input datasets in
                              file specified.
     -l_ncpl "LND_NCPL"       Number of CLM coupling time-steps in a day.
     -mask "landmask"         Type of land-mask (default, navy, gx3v5, gx1v5 etc.)
                              "-mask list" to list valid land masks.
     -namelist "namelist"     Specify namelist settings directly on the commandline by supplying
                              a string containing FORTRAN namelist syntax, e.g.,
                                 -namelist "&clm_inparm dt=1800 /"
     -[no-]note               Add note to output namelist  [do NOT add note] about the
                              arguments to build-namelist.
     -output_reals <file>     Output real parameters to the given output file.
     -rcp "value"             Representative concentration pathway (rcp) to use for
                              future scenarios.
                              "-rcp list" to list valid rcp settings.
     -s                       Turns on silent mode - only fatal messages issued.
     -test                    Enable checking that input datasets exist on local filesystem.
     -use_case "case"         Specify a use case which will provide default values.
                              "-use_case list" to list valid use-cases.
     -verbose [or -v]         Turn on verbose echoing of informational messages.
     -version                 Echo the SVN tag name used to check out this CLM distribution.


Note: The precedence for setting the values of namelist variables is (highest to lowest):
      0. namelist values set by specific command-line options, like, -d, -sim_year
             (i.e.  compset choice and CLM_BLDNML_OPTS, CLM_ACCELERATED_SPINUP, LND_TUNING_MODE env_run variables)
     (NOTE: If you try to contradict these settings by methods below, an error will be triggered)
      1. values set on the command-line using the -namelist option,
             (i.e. CLM_NAMELIST_OPTS env_run variable)
      2. values read from the file(s) specified by -infile,
             (i.e.  user_nl_clm files)
      4. values set from a use-case scenario, e.g., -use_case
             (i.e.  CLM_NML_USE_CASE env_run variable)
      5. values from the namelist defaults file.
EOF
}

#-------------------------------------------------------------------------------

sub process_commandline {
  # Process command-line options and return the hash
  my ($nl_flags) = @_;

  # Save the command line arguments to the script. NOTE: this must be
  # before GetOptions() is called because items are removed from from
  # the array!
  $nl_flags->{'cmdline'} = "@ARGV";

  my %opts = ( cimeroot              => undef,
               config                => "config_cache.xml",
               csmdata               => undef,
               co2_type              => undef,
               co2_ppmv              => undef,
               clm_demand            => "null",
               help                  => 0,
               glc_nec               => "default",
               l_ncpl                => undef,
               lnd_frac              => undef,
               dir                   => "$cwd",
               rcp                   => "default",
               sim_year              => "default",
               chk_res               => undef,
               note                  => undef,
               output_reals_filename => undef,
               res                   => "default",
               silent                => 0,
               ignore_warnings       => 0,
               mask                  => "default",
               test                  => 0,
               bgc                   => "default",
               envxml_dir            => ".",
               maxpft                => "default",
             );

  GetOptions(
             "cimeroot=s"                => \$opts{'cimeroot'},
             "clm_demand=s"              => \$opts{'clm_demand'},
             "co2_ppmv=f"                => \$opts{'co2_ppmv'},
             "co2_type=s"                => \$opts{'co2_type'},
             "config=s"                  => \$opts{'config'},
             "csmdata=s"                 => \$opts{'csmdata'},
             "envxml_dir=s"              => \$opts{'envxml_dir'},
             "ignore_warnings!"          => \$opts{'ignore_warnings'},
             "chk_res!"                  => \$opts{'chk_res'},
             "note!"                     => \$opts{'note'},
             "glc_nec=i"                 => \$opts{'glc_nec'},
             "d:s"                       => \$opts{'dir'},
             "h|help"                    => \$opts{'help'},
             "ignore_ic_date"            => \$opts{'ignore_ic_date'},
             "ignore_ic_year"            => \$opts{'ignore_ic_year'},
             "infile=s"                  => \$opts{'infile'},
             "lnd_frac=s"                => \$opts{'lnd_frac'},
             "l_ncpl=i"                  => \$opts{'l_ncpl'},
             "inputdata=s"               => \$opts{'inputdata'},
             "mask=s"                    => \$opts{'mask'},
             "namelist=s"                => \$opts{'namelist'},
             "res=s"                     => \$opts{'res'},
             "rcp=s"                     => \$opts{'rcp'},
             "s|silent"                  => \$opts{'silent'},
             "sim_year=s"                => \$opts{'sim_year'},
             "output_reals=s"            => \$opts{'output_reals_filename'},
             "clm_start_type=s"          => \$opts{'clm_start_type'},
             "test"                      => \$opts{'test'},
             "use_case=s"                => \$opts{'use_case'},
             "bgc=s"                     => \$opts{'bgc'},
             "maxpft=i"                  => \$opts{'maxpft'},
             "v|verbose"                 => \$opts{'verbose'},
             "version"                   => \$opts{'version'},
            )  or usage();

  # Give usage message.
  usage() if $opts{'help'};

  # Check for unparsed arguments
  if (@ARGV) {
    print "ERROR: unrecognized arguments: @ARGV\n";
    usage();
  }
  return %opts;
}

#-------------------------------------------------------------------------------

sub check_for_perl_utils {

  my $cfgdir = shift;
  my $opts_ref = shift;

  # Determine CIME root directory and perl5lib root directory
  my $cimeroot = $opts_ref->{'cimeroot'};
  if ( ! defined($cimeroot) ) {
    $cimeroot = "$cfgdir/../cime";
    if (      -d $cimeroot ) {
    } elsif ( -d "$cfgdir/../../../cime" ) {
      $cimeroot = "$cfgdir/../../../cime";
    } else {
      die <<"EOF";
** Cannot find the root of the cime directory  enter it using the -cimeroot option
   Did you run the checkout_externals scripts?
EOF
    }
  }

  my $perl5lib_dir = "$cimeroot/utils/perl5lib";

  #-----------------------------------------------------------------------------
  # Add $perl5lib_dir to the list of paths that Perl searches for modules
  my @dirs = ( $ProgDir, $cfgdir, "$perl5lib_dir");
  unshift @INC, @dirs;

  require config_files::clm_phys_vers;
  require namelist_files::LogMessages;

  my $locallog = namelist_files::LogMessages->new( $ProgName, $opts_ref );
  # The XML::Lite module is required to parse the XML files.
  (-f "$perl5lib_dir/XML/Lite.pm")  or
      $locallog->fatal_error("Cannot find perl module \"XML/Lite.pm\" in directory\n" .
                "\"$perl5lib_dir\"");

  # The Build::Config module provides utilities to access the configuration information
  # in the config_cache.xml file
  (-f "$perl5lib_dir/Build/Config.pm")  or
      $locallog->fatal_error("Cannot find perl module \"Build/Config.pm\" in directory\n" .
                "\"$perl5lib_dir\"");

  # The Build::NamelistDefinition module provides utilities to validate that the output
  # namelists are consistent with the namelist definition file
  (-f "$perl5lib_dir/Build/NamelistDefinition.pm")  or
      $locallog->fatal_error("Cannot find perl module \"Build/NamelistDefinition.pm\" in directory\n" .
		  "\"$perl5lib_dir\"");

  # The Build::NamelistDefaults module provides a utility to obtain default values of namelist
  # variables based on finding a best fit with the attributes specified in the defaults file.
  (-f "$perl5lib_dir/Build/NamelistDefaults.pm")  or
      $locallog->fatal_error("Cannot find perl module \"Build/NamelistDefaults.pm\" in directory\n" .
		  "\"$perl5lib_dir\"");

  # The Build::Namelist module provides utilities to parse input namelists, to query and modify
  # namelists, and to write output namelists.
  (-f "$perl5lib_dir/Build/Namelist.pm")  or
      $locallog->fatal_error("Cannot find perl module \"Build/Namelist.pm\" in directory\n" .
		  "\"$perl5lib_dir\"");


  # required cesm perl modules
  require XML::Lite;
  require Build::Config;
  require Build::NamelistDefinition;
  require Build::NamelistDefaults;
  require Build::Namelist;
  require Config::SetupTools;
}

#-------------------------------------------------------------------------------

sub read_configure_definition {
  # Read the configure definition and specific config_cache file for this case
  # configure are the build-time settings for CLM
  my ($cfgdir, $opts) = @_;

  $log->verbose_message("Setting CLM configuration script directory to $cfgdir");

  # Create a configuration object from the default config_definition file
  my $configfile;
  if ( -f $opts->{'config'} ) {
    $configfile = $opts->{'config'};
  } else {
    $configfile = "$cfgdir/config_files/config_definition.xml";
  }

  # Check that configuration cache file exists.
  $log->verbose_message("Using CLM configuration cache file $opts->{'config'}");
  if ( $configfile ne $opts->{'config'} ) {
    $log->fatal_error("Cannot find configuration cache file: \"$opts->{'config'}\"");
  }

  my $cfg = Build::Config->new("$configfile");

  return $cfg;
}

#-----------------------------------------------------------------------------------------------

sub read_namelist_definition {
  my ($cfgdir, $opts, $nl_flags, $physv) = @_;

  # The namelist definition file contains entries for all namelist
  # variables that can be output by build-namelist.
  my $phys = $physv->as_filename( );
  my @nl_definition_files = ( "$cfgdir/namelist_files/namelist_definition_drv.xml",
                              "$cfgdir/namelist_files/namelist_definition_$phys.xml" );
  foreach my $nl_defin_file  ( @nl_definition_files ) {
    (-f "$nl_defin_file")  or  $log->fatal_error("Cannot find namelist definition file \"$nl_defin_file\"");

    $log->verbose_message("Using namelist definition file $nl_defin_file");
  }

  # Create a namelist definition object.  This object provides a
  # method for verifying that the output namelist variables are in the
  # definition file, and are output in the correct namelist groups.
  my $definition = Build::NamelistDefinition->new( shift(@nl_definition_files) );
  foreach my $nl_defin_file ( @nl_definition_files ) {
    $definition->add( "$nl_defin_file" );
  }

  return $definition;
}

#-----------------------------------------------------------------------------------------------

sub read_envxml_case_files {
  # read the contents of the env*.xml files in the case directory
  my ($opts) = @_;

  my %envxml = ();
  if ( defined($opts->{'envxml_dir'}) ) {
      (-d $opts->{'envxml_dir'})  or  $log->fatal_error( "envxml_dir is not a directory" );
      my @files = glob( $opts->{'envxml_dir'}."/env_*xml" );
      ($#files >= 0)              or  $log->fatal_error( "there are no env_*xml files in the envxml_dir" );
      foreach my $file (@files) {
          $log->verbose_message( "Open env.xml file: $file" );
          my $xml = XML::Lite->new( "$file" );
          my @e   = $xml->elements_by_name('entry');
          while ( my $e = shift @e ) {
              my %a = $e->get_attributes();
              $envxml{$a{'id'}} = $a{'value'};
          }
      }
      foreach my $attr (keys %envxml) {
          if ( $envxml{$attr} =~ m/\$/ ) {
             $envxml{$attr} = SetupTools::expand_xml_var( $envxml{$attr}, \%envxml );
          }
      }
  } else {
      $log->fatal_error( "The -envxml_dir option was NOT given and it is a REQUIRED option" );
  }
  return( %envxml );
}

#-----------------------------------------------------------------------------------------------

sub read_namelist_defaults {
  my ($cfgdir, $opts, $nl_flags, $cfg, $physv) = @_;

  my $phys = $physv->as_filename( );
  # The namelist defaults file contains default values for all required namelist variables.
  my @nl_defaults_files = ( "$cfgdir/namelist_files/namelist_defaults_overall.xml",
                            "$cfgdir/namelist_files/namelist_defaults_$phys.xml" );

  # Add the location of the use case defaults files to the options hash
  $opts->{'use_case_dir'} = "$cfgdir/namelist_files/use_cases";

  if (defined $opts->{'use_case'}) {
    if ( $opts->{'use_case'} ne "list" ) {
      unshift( @nl_defaults_files, "$opts->{'use_case_dir'}/$opts->{'use_case'}.xml" );
    }
  }

  foreach my $nl_defaults_file ( @nl_defaults_files ) {
    (-f "$nl_defaults_file")  or  $log->fatal_error("Cannot find namelist defaults file \"$nl_defaults_file\"");

    $log->verbose_message("Using namelist defaults file $nl_defaults_file");
  }

  # Create a namelist defaults object.  This object provides default
  # values for variables contained in the input defaults file.  The
  # configuration object provides attribute values that are relevent
  # for the CLM executable for which the namelist is being produced.
  my $defaults = Build::NamelistDefaults->new( shift( @nl_defaults_files ), $cfg);
  foreach my $nl_defaults_file ( @nl_defaults_files ) {
    $defaults->add( "$nl_defaults_file" );
  }
  return $defaults;
}

#-------------------------------------------------------------------------------

sub check_cesm_inputdata {
  # Check that the CESM inputdata root directory has been specified.  This must be
  # a local or nfs mounted directory.

  my ($opts, $nl_flags) = @_;

  $nl_flags->{'inputdata_rootdir'} = undef;
  if (defined($opts->{'csmdata'})) {
    $nl_flags->{'inputdata_rootdir'} = $opts->{'csmdata'};
  }
  elsif (defined $ENV{'CSMDATA'}) {
    $nl_flags->{'inputdata_rootdir'} = $ENV{'CSMDATA'};
  }
  else {
    $log->fatal_error("CESM inputdata root directory must be specified by either -csmdata\n" .
                "argument or by the CSMDATA environment variable.");
  }
  if ( ! defined($ENV{'DIN_LOC_ROOT'}) ) {
    $ENV{'DIN_LOC_ROOT'} = $nl_flags->{'inputdata_rootdir'};
  }

  if ($opts->{'test'}) {
    (-d $nl_flags->{'inputdata_rootdir'})  or  $log->fatal_error("CESM inputdata root is not a directory: \"$nl_flags->{'inputdata_rootdir'}\"");
  }

  $log->verbose_message("CESM inputdata root directory: $nl_flags->{'inputdata_rootdir'}");
}

#-------------------------------------------------------------------------------

sub process_namelist_user_input {
  # Process the user input in general by order of precedence.  At each point
  # we'll only add new values to the namelist and not overwrite
  # previously specified specified values which have higher
  # precedence. The one exception to this rule are the specifc command-line
  # options which are done last as if the user contradicts these settings
  # CLM build-namelist will abort with an error.
  #
  # 1. values set on the command-line using the -namelist option,
  #         (i.e. CLM_NAMELIST_OPTS env_run variable)
  # 2. values read from the file(s) specified by -infile,
  #         (i.e.  user_nl_clm files)
  # After the above are done the command line options are processed and they
  # are made sure the user hasn't contradicted any of their settings with
  # anything above. Because of this they are condsidered to have the highest
  # precedence.
  # 0. namelist values set by specific command-line options, like, -d, -sim_year
  #         (i.e.  CLM_BLDNML_OPTS env_run variable)
  # The results of these are needed for the final two user input
  # 4. values set from a use-case scenario, e.g., -use_case
  #         (i.e.  CLM_NML_USE_CASE env_run variable)
  #
  # Finally after all the above is done, the defaults are found from the
  # namelist defaults file (outside of this routine).
  #


  my ($opts, $nl_flags, $definition, $defaults, $nl, $cfg, $envxml_ref, $physv) = @_;

  # Get the inputs that will be coming from the user...
  process_namelist_commandline_namelist($opts, $definition, $nl, $envxml_ref);
  process_namelist_commandline_infile($opts, $definition, $nl, $envxml_ref);

  # Apply the commandline options and make sure the user didn't change it above
  process_namelist_commandline_options($opts, $nl_flags, $definition, $defaults, $nl, $cfg, $physv);

  # The last two process command line arguments for use_case
  # They require that process_namelist_commandline_options was called before this
  process_namelist_commandline_use_case($opts, $nl_flags, $definition, $defaults, $nl, $cfg, $envxml_ref, $physv);

  # Set the start_type by the command line setting for clm_start_type
  process_namelist_commandline_clm_start_type($opts, $nl_flags, $definition, $defaults, $nl);

}

#-------------------------------------------------------------------------------

sub process_namelist_commandline_options {
  # First process the commandline args that provide specific namelist values.
  #
  # First get the command-line specified overall values or their defaults
  # Obtain default values for the following build-namelist input arguments
  # : res, mask, rcp, sim_year, sim_year_range.
  #
  my ($opts, $nl_flags, $definition, $defaults, $nl, $cfg, $physv) = @_;

  setup_cmdl_chk_res($opts, $defaults);
  setup_cmdl_resolution($opts, $nl_flags, $definition, $defaults);
  setup_cmdl_mask($opts, $nl_flags, $definition, $defaults, $nl);
  setup_cmdl_bgc($opts, $nl_flags, $definition, $defaults, $nl, $cfg, $physv);
  setup_cmdl_maxpft($opts, $nl_flags, $definition, $defaults, $nl, $cfg, $physv);
  setup_cmdl_glc_nec($opts, $nl_flags, $definition, $defaults, $nl);
  setup_cmdl_rcp($opts, $nl_flags, $definition, $defaults, $nl);
  setup_cmdl_simulation_year($opts, $nl_flags, $definition, $defaults, $nl);
  setup_cmdl_run_type($opts, $nl_flags, $definition, $defaults, $nl);
  setup_cmdl_output_reals($opts, $nl_flags, $definition, $defaults, $nl, $physv);
}

#-------------------------------------------------------------------------------

sub setup_cmdl_chk_res {
  my ($opts, $defaults) = @_;

  my $var = "chk_res";
  if ( ! defined($opts->{$var}) ) {
    $opts->{$var} = $defaults->get_value($var);
  }
}

sub setup_cmdl_resolution {
  my ($opts, $nl_flags, $definition, $defaults) = @_;

  my $var = "res";
  my $val;

  if ( $opts->{$var} ne "default" ) {
    $val = $opts->{$var};
  } else {
    $val= $defaults->get_value($var);
  }

  $nl_flags->{'res'} = $val;
  $log->verbose_message("CLM atm resolution is $nl_flags->{'res'}");
  $opts->{$var} = $val;
  if ( $opts->{'chk_res'} ) {
    $val = &quote_string( $nl_flags->{'res'} );
    if (  ! $definition->is_valid_value( $var, $val ) ) {
      my @valid_values   = $definition->get_valid_values( $var );
      $log->fatal_error("$var has a value ($val) that is NOT valid. Valid values are: @valid_values");
    }
  }
}

#-------------------------------------------------------------------------------

sub setup_cmdl_mask {
  my ($opts, $nl_flags, $definition, $defaults, $nl) = @_;

  my $var = "mask";
  my $val;

  if ( $opts->{$var} ne "default" ) {
    $val = $opts->{$var};
  } else {
    my %tmp = ( 'hgrid'=>$nl_flags->{'res'} );
    $val = $defaults->get_value($var, \%tmp );
  }

  $nl_flags->{'mask'} = $val;
  $opts->{'mask'} = $nl_flags->{'mask'};
  if ( $opts->{'chk_res'} ) {
    $val = &quote_string( $val );
    my $group = $definition->get_group_name($var);
    $nl->set_variable_value($group, $var, $val);
    if (  ! $definition->is_valid_value( $var, $val ) ) {
      my @valid_values   = $definition->get_valid_values( $var );
      $log->fatal_error("$var has a value ($val) that is NOT valid. Valid values are: @valid_values");
    }
  }
  $log->verbose_message("CLM land mask is $nl_flags->{'mask'}");
}

#-------------------------------------------------------------------------------
sub setup_cmdl_bgc {
  # BGC - alias for group of biogeochemistry related use_XXX namelists

  my ($opts, $nl_flags, $definition, $defaults, $nl, $cfg, $physv) = @_;

  my $val;
  my $var = "bgc";

  $val = $opts->{$var};
  $nl_flags->{'bgc_mode'} = $val;

  my $var = "bgc_mode";
  if ( $nl_flags->{$var} eq "default" ) {
     $nl_flags->{$var} = $defaults->get_value($var);
  }
  my $group = $definition->get_group_name($var);
  $nl->set_variable_value($group, $var, quote_string( $nl_flags->{$var} ) );
  if (  ! $definition->is_valid_value( $var, quote_string( $nl_flags->{$var}) ) ) {
    my @valid_values   = $definition->get_valid_values( $var );
    $log->fatal_error("$var has a value (".$nl_flags->{$var}.") that is NOT valid. Valid values are: @valid_values");
  }
  $log->verbose_message("Using $nl_flags->{$var} for bgc.");

  # now set the actual name list variables based on the bgc alias
  if ($nl_flags->{$var} eq "bgc" ) {
    $nl_flags->{'use_cn'} = ".true.";
  } else {
    $nl_flags->{'use_cn'} = ".false.";
  }
  if ( defined($nl->get_value("use_cn")) && ($nl_flags->{'use_cn'} ne $nl->get_value("use_cn")) ) {
    $log->fatal_error("The namelist variable use_cn is inconsistent with the -bgc option");
  }

  {
	# If the variable has already been set use it, if not set to the value defined by the bgc_mode
	my @list  = (  "use_lch4", "use_nitrif_denitrif", "use_vertsoilc", "use_century_decomp" );
	my $ndiff = 0;
        my %settings = ( 'bgc_mode'=>$nl_flags->{'bgc_mode'} );
	foreach my $var ( @list ) {
            my $default_setting = $defaults->get_value($var, \%settings );
	    if ( ! defined($nl->get_value($var))  ) {
		$nl_flags->{$var} = $default_setting;
	    } else {
		if ( $nl->get_value($var) ne $default_setting ) {
		    $ndiff += 1;
		}
		$nl_flags->{$var} = $nl->get_value($var);
	    }
	    $val = $nl_flags->{$var};
	    my $group = $definition->get_group_name($var);
	    $nl->set_variable_value($group, $var, $val);
	    if (  ! $definition->is_valid_value( $var, $val ) ) {
		my @valid_values   = $definition->get_valid_values( $var );
		$log->fatal_error("$var has a value ($val) that is NOT valid. Valid values are: @valid_values");
	    }
	}
	# If all the variables are different report it as an error
	if ( $ndiff == ($#list + 1) ) {
	    $log->fatal_error("You are contradicting the -bgc setting with the namelist variables: @list" );
	}
  }

  # Now set use_cn
  foreach $var ( "use_cn" ) {
     $val = $nl_flags->{$var};
     $group = $definition->get_group_name($var);
     $nl->set_variable_value($group, $var, $val);
     if (  ! $definition->is_valid_value( $var, $val ) ) {
       my @valid_values   = $definition->get_valid_values( $var );
       $log->fatal_error("$var has a value ($val) that is NOT valid. Valid values are: @valid_values");
     }
  }
  my $var = "use_fun";
  if ( ! defined($nl->get_value($var)) ) {
     add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $var,
                 'phys'=>$nl_flags->{'phys'}, 'use_cn'=>$nl_flags->{'use_cn'},
                 'use_nitrif_denitrif'=>$nl_flags->{'use_nitrif_denitrif'} );
  }
  if ( (! &value_is_true($nl_flags->{'use_nitrif_denitrif'}) ) && &value_is_true($nl->get_value('use_fun')) ) {
     $log->fatal_error("When FUN is on, use_nitrif_denitrif MUST also be on!");
  }
} # end bgc


#-------------------------------------------------------------------------------

sub setup_cmdl_maxpft {
  my ($opts, $nl_flags, $definition, $defaults, $nl, $cfg, $physv) = @_;

  my $val;
  my $var = "maxpft";
  my $maxpatchpft = 17;
  if ( $opts->{$var} ne "default") {
    $val = $opts->{$var};
  } else {
    $val = $maxpatchpft;
  }
  $nl_flags->{'maxpft'} = $val;

  if ( ($nl_flags->{'bgc_mode'} ne "sp") && ($nl_flags->{'maxpft'} != $maxpatchpft) ) {
    $log->fatal_error("** For CN or BGC mode you MUST set max patch PFT's to $maxpatchpft\n" .
                "**\n" .
                "** Set the bgc mode, crop and maxpft by the following means from highest to lowest precedence:\n" .
                "** * by the command-line options -bgc and -maxpft\n" .
                "** * by a default configuration file, specified by -defaults\n" .
                "**");
  }
  if ( $nl_flags->{'maxpft'} > $maxpatchpft ) {
    $log->fatal_error("** Max patch PFT's can NOT exceed $maxpatchpft\n" .
                "**\n" .
                "** Set maxpft by the following means from highest to lowest precedence:\n" .
                "** * by the command-line options -maxpft\n" .
                "** * by a default configuration file, specified by -defaults\n" .
                "**");
  }
  if ( $nl_flags->{'maxpft'} != $maxpatchpft ) {
    $log->warning("running with maxpft NOT equal to $maxpatchpft is " .
            "NOT validated / scientifically supported." );
  }
  $log->verbose_message("Using $nl_flags->{'maxpft'} for maxpft.");

  $var = "maxpatch_pft";
  $val = $nl_flags->{'maxpft'};
  my $group = $definition->get_group_name($var);
  $nl->set_variable_value($group, $var, $val);
  if (  ! $definition->is_valid_value( $var, $val ) ) {
    my @valid_values   = $definition->get_valid_values( $var );
    $log->fatal_error("$var has a value ($val) that is NOT valid. Valid values are: @valid_values");
  }
}

#-------------------------------------------------------------------------------

sub setup_cmdl_glc_nec {
  my ($opts, $nl_flags, $definition, $defaults, $nl) = @_;

  my $val;
  my $var = "glc_nec";

  if ( $opts->{$var} ne "default" ) {
    $val = $opts->{$var};
  } else {
    $val = $defaults->get_value($var);
  }

  $nl_flags->{'glc_nec'} = $val;
  $opts->{'glc_nec'} = $val;
  my $group = $definition->get_group_name($var);
  $nl->set_variable_value($group, $var, $val);
  if (  ! $definition->is_valid_value( $var, $val ) ) {
    my @valid_values   = $definition->get_valid_values( $var );
    $log->fatal_error("$var has a value ($val) that is NOT valid. Valid values are: @valid_values");
  }
  $log->verbose_message("Glacier number of elevation classes is $val");
}

#-------------------------------------------------------------------------------

sub setup_cmdl_rcp {
  # representative concentration pathway
  my ($opts, $nl_flags, $definition, $defaults, $nl) = @_;

  my $val;
  my $var = "rcp";
  if ( $opts->{$var} ne "default" ) {
    $val = $opts->{$var};
  } else {
    $val = $defaults->get_value($var);
  }
  $nl_flags->{'rcp'} = $val;
  $opts->{'rcp'} = $nl_flags->{'rcp'};
  my $group = $definition->get_group_name($var);
  $nl->set_variable_value($group, $var, $val);
  if (  ! $definition->is_valid_value( $var, $val ) ) {
    my @valid_values   = $definition->get_valid_values( $var );
    $log->fatal_error("$var has a value ($val) that is NOT valid. Valid values are: @valid_values");
  }
  $log->verbose_message("CLM future scenario representative concentration is $nl_flags->{'rcp'}");
}

#-------------------------------------------------------------------------------

sub setup_cmdl_simulation_year {
  my ($opts, $nl_flags, $definition, $defaults, $nl, $cfg) = @_;

  my $val;
  my $var = "sim_year";
  if ( $opts->{$var} ne "default" ) {
    $val = $opts->{$var};
  } else {
    $val = $defaults->get_value($var);
  }

  $nl_flags->{'sim_year_range'} = $defaults->get_value("sim_year_range");
  $nl_flags->{'sim_year'}       = $val;
  if ( $val =~ /([0-9]+)-([0-9]+)/ ) {
    $nl_flags->{'sim_year'}       = $1;
    $nl_flags->{'sim_year_range'} = $val;
  }
  $val = $nl_flags->{'sim_year'};
  my $group = $definition->get_group_name($var);
  $nl->set_variable_value($group, $var, $val );
  if (  ! $definition->is_valid_value( $var, $val, 'noquotes'=>1 ) ) {
    my @valid_values   = $definition->get_valid_values( $var );
    $log->fatal_error("$var of $val is NOT valid. Valid values are: @valid_values");
  }
  $nl->set_variable_value($group, $var, $val );
  $log->verbose_message("CLM sim_year is $nl_flags->{'sim_year'}");

  $var = "sim_year_range";
  $val = $nl_flags->{'sim_year_range'};
  if ( $val ne "constant" ) {
    $opts->{$var}   = $val;
    $group = $definition->get_group_name($var);
    $nl->set_variable_value($group, $var, $val );
    if (  ! $definition->is_valid_value( $var, $val, 'noquotes'=>1 ) ) {
      my @valid_values   = $definition->get_valid_values( $var );
      $log->fatal_error("$var of $val is NOT valid. Valid values are: @valid_values");
    }
    $val = "'".$defaults->get_value($var)."'";
    $nl->set_variable_value($group, $var, $val );
    $log->verbose_message("CLM sim_year_range is $nl_flags->{'sim_year_range'}");
  }
}

#-------------------------------------------------------------------------------

sub setup_cmdl_run_type {
  my ($opts, $nl_flags, $definition, $defaults, $nl) = @_;

  my $val;
  my $var = "clm_start_type";
  if (defined $opts->{$var}) {
    if ($opts->{$var} eq "default" ) {
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $var, 
                  'use_cndv'=>$nl_flags->{'use_cndv'} );
    } else {
      my $group = $definition->get_group_name($var);
      $nl->set_variable_value($group, $var, quote_string( $opts->{$var} ) );
    }
  } else {
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $var, 
                  'use_cndv'=>$nl_flags->{'use_cndv'} );
  }
  $nl_flags->{'clm_start_type'} = $nl->get_value($var);
}

#-------------------------------------------------------------------------------

sub setup_cmdl_output_reals {
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  my $var = "output_reals_filename";
  my $file = $opts->{$var};
  if ( defined($file) ) {
     # Make sure can open file and if not die with an error
     my $fh = IO::File->new($file, '>') or $log->fatal_error("can't create real parameter filename: $file");
     $fh->close();
  }
}

#-------------------------------------------------------------------------------

sub process_namelist_commandline_namelist {
  # Process the commandline '-namelist' arg.
  my ($opts, $definition, $nl, $envxml_ref) = @_;

  if (defined $opts->{'namelist'}) {
    # Parse commandline namelist
    my $nl_arg = Build::Namelist->new($opts->{'namelist'});

    # Validate input namelist -- trap exceptions
    my $nl_arg_valid;
    eval { $nl_arg_valid = $definition->validate($nl_arg); };
    if ($@) {
      $log->fatal_error("Invalid namelist variable in commandline arg '-namelist'.\n $@");
    }
    # Go through all variables and expand any XML env settings in them
    expand_xml_variables_in_namelist( $nl_arg_valid, $envxml_ref );

    # Merge input values into namelist.  Previously specified values have higher precedence
    # and are not overwritten.
    $nl->merge_nl($nl_arg_valid);
  }
}

#-------------------------------------------------------------------------------

sub process_namelist_commandline_infile {
  # Process the commandline '-infile' arg.
  my ($opts, $definition, $nl, $envxml_ref) = @_;

  if (defined $opts->{'infile'}) {
    my @infiles = split( /,/, $opts->{'infile'} );
    foreach my $infile ( @infiles ) {
      # Make sure a valid file was found
      if (    -f "$infile" ) {
        # Otherwise abort as a valid file doesn't exist
      } else {
        $log->fatal_error("input namelist file does NOT exist $infile.\n $@");
      }
      # Parse namelist input from the next file
      my $nl_infile = Build::Namelist->new($infile);

      # Validate input namelist -- trap exceptions
      my $nl_infile_valid;
      eval { $nl_infile_valid = $definition->validate($nl_infile); };
      if ($@) {
        $log->fatal_error("Invalid namelist variable in '-infile' $infile.\n $@");
      }
      # Go through all variables and expand any XML env settings in them
      expand_xml_variables_in_namelist( $nl_infile_valid, $envxml_ref );

      # Merge input values into namelist.  Previously specified values have higher precedence
      # and are not overwritten.
      $nl->merge_nl($nl_infile_valid);
    }
  }
}

#-------------------------------------------------------------------------------

sub process_namelist_commandline_use_case {
  # Now process the -use_case arg.
  my ($opts, $nl_flags, $definition, $defaults, $nl, $cfg, $envxml_ref, $physv) = @_;

  if (defined $opts->{'use_case'}) {

    # The use case definition is contained in an xml file with the same format as the defaults file.
    # Create a new NamelistDefaults object.
    my $uc_defaults = Build::NamelistDefaults->new("$opts->{'use_case_dir'}/$opts->{'use_case'}.xml", $cfg);

    my %settings;
    $settings{'res'}            = $nl_flags->{'res'};
    $settings{'rcp'}            = $nl_flags->{'rcp'};
    $settings{'mask'}           = $nl_flags->{'mask'};
    $settings{'sim_year'}       = $nl_flags->{'sim_year'};
    $settings{'sim_year_range'} = $nl_flags->{'sim_year_range'};
    $settings{'phys'}           = $nl_flags->{'phys'};
    $settings{'use_cn'}      = $nl_flags->{'use_cn'};
    $settings{'use_cndv'}    = $nl_flags->{'use_cndv'};
    $settings{'cnfireson'}   = $nl_flags->{'cnfireson'};
    # Loop over the variables specified in the use case.
    # Add each one to the namelist.
    my @vars = $uc_defaults->get_variable_names();
    my $nl_usecase = Build::Namelist->new();
    foreach my $var (@vars) {
      my $val = $uc_defaults->get_value($var, \%settings );

      if ( defined($val) ) {
        $log->message("CLM adding use_case $opts->{'use_case'} defaults for var '$var' with val '$val'");

        add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl_usecase, $var, 'val'=>$val);
      }
    }
    # Go through all variables and expand any XML env settings in them
    expand_xml_variables_in_namelist( $nl_usecase, $envxml_ref );

    # Merge input values into namelist.  Previously specified values have higher precedence
    # and are not overwritten.
    $nl->merge_nl($nl_usecase);
  }
}

#-------------------------------------------------------------------------------

sub process_namelist_commandline_clm_start_type {
  # Set the start_type according to the command line clm_start_type option

  my ($opts, $nl_flags, $definition, $defaults, $nl) = @_;

  # Run type for driver namelist - note that arb_ic implies that the run is startup
  my $var = "start_type";
  if ($nl_flags->{'clm_start_type'} eq "'cold'" || $nl_flags->{'clm_start_type'} eq "'arb_ic'") {
    # Add default is used here, but the value is explicitly set
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $var, 'val'=>'startup'   );
  } else {
    # Add default is used here, but the value is explicitly set
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $var, 'val'=>$nl_flags->{'clm_start_type'} );
  }
}

#-------------------------------------------------------------------------------

sub process_namelist_inline_logic {
  # Use the namelist default object to add default values for required
  # namelist variables that have not been previously set.
  my ($opts, $nl_flags, $definition, $defaults, $nl, $cfg, $envxml_ref, $physv) = @_;


  ##############################
  # namelist group: clm_inparm #
  ##############################
  setup_logic_lnd_frac($opts, $nl_flags, $definition, $defaults, $nl, $envxml_ref);
  setup_logic_co2_type($opts, $nl_flags, $definition, $defaults, $nl);
  setup_logic_start_type($opts, $nl_flags, $nl);
  setup_logic_delta_time($opts, $nl_flags, $definition, $defaults, $nl);
  setup_logic_decomp_performance($opts,  $nl_flags, $definition, $defaults, $nl);
  setup_logic_glacier($opts, $nl_flags, $definition, $defaults, $nl,  $envxml_ref, $physv);
  setup_logic_dynamic_plant_nitrogen_alloc($opts, $nl_flags, $definition, $defaults, $nl, $physv);
  setup_logic_hydrstress($opts,  $nl_flags, $definition, $defaults, $nl, $physv);
  setup_logic_dynamic_roots($opts,  $nl_flags, $definition, $defaults, $nl, $physv);
  setup_logic_params_file($opts,  $nl_flags, $definition, $defaults, $nl, $physv);
  setup_logic_create_crop_landunit($opts,  $nl_flags, $definition, $defaults, $nl, $physv);
  setup_logic_soilstate($opts,  $nl_flags, $definition, $defaults, $nl, $physv);
  setup_logic_demand($opts, $nl_flags, $definition, $defaults, $nl, $physv);
  setup_logic_surface_dataset($opts,  $nl_flags, $definition, $defaults, $nl, $physv);
  setup_logic_initial_conditions($opts, $nl_flags, $definition, $defaults, $nl, $physv);
  setup_logic_snowpack($opts,  $nl_flags, $definition, $defaults, $nl, $physv);

  #########################################
  # namelist group: atm2lnd_inparm
  #########################################
  setup_logic_atm_forcing($opts,  $nl_flags, $definition, $defaults, $nl, $physv);

  #########################################
  # namelist group: lnd2atm_inparm
  #########################################
  setup_logic_lnd2atm($opts,  $nl_flags, $definition, $defaults, $nl, $physv);

  ###############################
  # namelist group: clmu_inparm #
  ###############################
  setup_logic_urban($opts,  $nl_flags, $definition, $defaults, $nl, $physv);

  ##################################
  # namelist group: bgc_shared
  ##################################
  setup_logic_bgc_shared($opts,  $nl_flags, $definition, $defaults, $nl, $physv);

  #############################################
  # namelist group: soilwater_movement_inparm #
  #############################################
  setup_logic_soilwater_movement($opts,  $nl_flags, $definition, $defaults, $nl, $physv);

  #############################################
  # namelist group: rooting_profile_inparm    #
  #############################################
  setup_logic_rooting_profile($opts,  $nl_flags, $definition, $defaults, $nl, $physv);

  ####################################
  # namelist group: cnvegcarbonstate #
  ####################################
  setup_logic_cnvegcarbonstate($opts,  $nl_flags, $definition, $defaults, $nl, $physv);

  #############################################
  # namelist group: soil_resis_inparm #
  #############################################
  setup_logic_soil_resis($opts,  $nl_flags, $definition, $defaults, $nl, $physv);

  #############################################
  # namelist group: canopyhydrology_inparm #
  #############################################
  setup_logic_canopyhydrology($opts,  $nl_flags, $definition, $defaults, $nl, $physv);

  #####################################
  # namelist group: clm_canopy_inparm #
  #####################################
  setup_logic_canopy($opts,  $nl_flags, $definition, $defaults, $nl, $physv);

  #######################################################################
  # namelist groups: clm_hydrology1_inparm and clm_soilhydrology_inparm #
  #######################################################################
  setup_logic_hydrology_switches($nl, $physv);

}

#-------------------------------------------------------------------------------

sub setup_logic_lnd_frac {

  my ($opts, $nl_flags, $definition, $defaults, $nl, $envxml_ref) = @_;

  my $var = "lnd_frac";
  if ( defined($opts->{$var}) ) {
    if ( defined($nl->get_value('fatmlndfrc')) ) {
      $log->fatal_error("Can NOT set both -lnd_frac option (set via LND_DOMAIN_PATH/LND_DOMAIN_FILE " .
                  "env variables) AND fatmlndfrac on namelist");
    }
    my $lnd_frac = SetupTools::expand_xml_var( $opts->{$var}, $envxml_ref);
    add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'fatmlndfrc','val'=>$lnd_frac );
  }

  # Get the fraction file
  if (defined $nl->get_value('fatmlndfrc')) {
    # do nothing - use value provided by config_grid.xml and clm.cpl7.template
  } else {
    $log->fatal_error("fatmlndfrc was NOT sent into CLM build-namelist.");
  }
}

#-------------------------------------------------------------------------------

sub setup_logic_co2_type {
  my ($opts, $nl_flags, $definition, $defaults, $nl) = @_;

  my $var = "co2_type";
  if ( defined($opts->{$var}) ) {
    if ( ! defined($nl->get_value($var)) ) {
      add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'co2_type','val'=>"$opts->{'co2_type'}");
    } else {
      $log->fatal_error("co2_type set on namelist as well as -co2_type option.");
    }
  }
  add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'co2_type');
  if ( $nl->get_value('co2_type') =~ /constant/ ) {
    my $var = 'co2_ppmv';
    if ( defined($opts->{$var}) ) {
      if ( $opts->{$var} <= 0.0 ) {
        $log->fatal_error("co2_ppmv can NOT be less than or equal to zero.");
      }
      my $group = $definition->get_group_name($var);
      $nl->set_variable_value($group, $var, $opts->{$var});
    } else {
      add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $var, 'sim_year'=>$nl_flags->{'sim_year'} );
    }
  }
}

#-------------------------------------------------------------------------------

sub setup_logic_start_type {
  my ($opts, $nl_flags, $nl) = @_;

  my $var = "start_type";
  my $drv_start_type = $nl->get_value($var);
  my $my_start_type  = $nl_flags->{'clm_start_type'};
  my $nsrest         = $nl->get_value('override_nsrest');

  if ( defined($nsrest) ) {
    if ( $nsrest == 0 ) { $my_start_type = "startup";  }
    if ( $nsrest == 1 ) { $my_start_type = "continue"; }
    if ( $nsrest == 3 ) { $my_start_type = "branch";   }
    if ( "$my_start_type" eq "$drv_start_type" ) {
      $log->fatal_error("no need to set override_nsrest to same as start_type.");
    }
    if ( "$drv_start_type" !~ /startup/ ) {
      $log->fatal_error("can NOT set override_nsrest if driver is NOT a startup type.");
    }
  }

  if ( $my_start_type =~ /branch/ ) {
    if (not defined $nl->get_value('nrevsn')) {
      $log->fatal_error("nrevsn is required for a branch type.");
    }
  } else {
    if (defined $nl->get_value('nrevsn')) {
      $log->fatal_error("nrevsn should ONLY be set for a branch type.");
    }
  }
}

#-------------------------------------------------------------------------------

sub setup_logic_delta_time {
  my ($opts, $nl_flags, $definition, $defaults, $nl) = @_;

  if ( defined($opts->{'l_ncpl'}) ) {
    my $l_ncpl = $opts->{'l_ncpl'};
    if ( $l_ncpl <= 0 ) {
      $log->fatal_error("bad value for -l_ncpl option.");
    }
    my $val = ( 3600 * 24 ) / $l_ncpl;
    my $dtime = $nl->get_value('dtime');
    if ( ! defined($dtime)  ) {
      add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'dtime', 'val'=>$val);
    } elsif ( $dtime ne $val ) {
      $log->fatal_error("can NOT set both -l_ncpl option (via LND_NCPL env variable) AND dtime namelist variable.");
    }
  } else {
    add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'dtime', 'hgrid'=>$nl_flags->{'res'});
  }
}

#-------------------------------------------------------------------------------

sub setup_logic_decomp_performance {
  my ($opts, $nl_flags, $definition, $defaults, $nl) = @_;

  # Set the number of segments per clump
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'nsegspc', 'hgrid'=>$nl_flags->{'res'});
}

#-------------------------------------------------------------------------------

sub setup_logic_glacier {
  #
  # Glacier multiple elevation class options
  #
  my ($opts, $nl_flags, $definition, $defaults, $nl, $envxml_ref, $physv) = @_;

  my $var = "maxpatch_glcmec";
  add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $var, 'val'=>$nl_flags->{'glc_nec'} );

  my $val = $nl->get_value($var);
  if ( $val != $nl_flags->{'glc_nec'} ) {
    $log->fatal_error("$var set to $val does NOT agree with -glc_nec argument of $nl_flags->{'glc_nec'} (set with GLC_NEC env variable)");
  }

  if ( $nl_flags->{'glc_nec'} < 1 ) {
     $log->fatal_error("For clm4_5 and later, GLC_NEC must be at least 1.");
  }

  add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'glc_snow_persistence_max_days');

  # Dependence of albice on glc_nec has gone away starting in CLM4_5. Thus, we
  # can remove glc_nec from the following call once we ditch CLM4_0.
  add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'albice', 'glc_nec'=>$nl_flags->{'glc_nec'});
  add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'glacier_region_behavior');
  add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'glacier_region_melt_behavior');
  add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'glacier_region_ice_runoff_behavior');
}

#-------------------------------------------------------------------------------

sub setup_logic_params_file {
  # get param data. For 4_0, pft-physiology, for 4_5 old
  # pft-physiology was used but now now includes CN and BGC century
  # parameters.
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'paramfile', 
              'phys'=>$nl_flags->{'phys'},
              'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
}

#-------------------------------------------------------------------------------

sub setup_logic_create_crop_landunit {
  # Create crop land unit
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  my $var = 'create_crop_landunit';
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $var );
}
#-------------------------------------------------------------------------------

sub setup_logic_urban {
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'building_temp_method');
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'urban_hac');
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'urban_traffic');
}

#-------------------------------------------------------------------------------

sub error_if_set {
   # do a fatal_error and exit if any of the input variable names are set
   my ($nl, $error, @list) = @_;
   foreach my $var ( @list ) {
      if ( defined($nl->get_value($var)) ) {
        $log->fatal_error( "$var $error" );
      }
   }
}


#-------------------------------------------------------------------------------

sub setup_logic_soilstate {
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

 add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'organic_frac_squared' );
 add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'soil_layerstruct' );
 add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'use_bedrock' );
}

#-------------------------------------------------------------------------------

sub setup_logic_demand {
  #
  # Deal with options that the user has said are required...
  #
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  my %settings;
  $settings{'hgrid'}          = $nl_flags->{'res'};
  $settings{'sim_year'}       = $nl_flags->{'sim_year'};
  $settings{'sim_year_range'} = $nl_flags->{'sim_year_range'};
  $settings{'mask'}           = $nl_flags->{'mask'};
  $settings{'rcp'}            = $nl_flags->{'rcp'};
  $settings{'glc_nec'}        = $nl_flags->{'glc_nec'};
  # necessary for demand to be set correctly
  $settings{'use_cn'}              = $nl_flags->{'use_cn'};
  $settings{'use_cndv'}            = $nl_flags->{'use_cndv'};
  $settings{'use_lch4'}            = $nl_flags->{'use_lch4'};
  $settings{'use_nitrif_denitrif'} = $nl_flags->{'use_nitrif_denitrif'};
  $settings{'use_vertsoilc'}       = $nl_flags->{'use_vertsoilc'};
  $settings{'use_century_decomp'}  = $nl_flags->{'use_century_decomp'};

  my $demand = $nl->get_value('clm_demand');
  if (defined($demand)) {
    $demand =~ s/\'//g;   # Remove quotes
    if ( $demand =~ /.+/ ) {
      $opts->{'clm_demand'} .= ",$demand";
    }
  }

  $demand = $defaults->get_value('clm_demand', \%settings);
  if (defined($demand)) {
    $demand =~ s/\'//g;   # Remove quotes
    if ( $demand =~ /.+/ ) {
      $opts->{'clm_demand'} .= ",$demand";
    }
  }

  my @demandlist = split( ",", $opts->{'clm_demand'} );
  foreach my $item ( @demandlist ) {
    if ( $item eq "null" ) {
      next;
    }
    if ( $item eq "finidat" ) {
        $log->fatal_error( "Do NOT put findat in the clm_demand list, set the clm_start_type=startup so initial conditions are required");
    }
    add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $item, %settings );
  }
}

#-------------------------------------------------------------------------------

sub setup_logic_surface_dataset {
  #
  # Get surface dataset after flanduse_timeseries so that we can get surface data
  # consistent with it
  # MUST BE AFTER: setup_logic_demand which is where flanduse_timeseries is set
  #
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  $nl_flags->{'flanduse_timeseries'} = "null";
  my $flanduse_timeseries = $nl->get_value('flanduse_timeseries');
  if (defined($flanduse_timeseries)) {
    $flanduse_timeseries =~ s!(.*)/!!;
    $flanduse_timeseries =~ s/\'//;
    $flanduse_timeseries =~ s/\"//;
    if ( $flanduse_timeseries ne "" ) {
      $nl_flags->{'flanduse_timeseries'} = $flanduse_timeseries;
    }
  }
  $flanduse_timeseries = $nl_flags->{'flanduse_timeseries'};

  if ($flanduse_timeseries ne "null" && &value_is_true($nl_flags->{'use_cndv'}) ) {
      $log->fatal_error( "dynamic PFT's (setting flanduse_timeseries) are incompatible with dynamic vegetation (use_cndv=.true)." );
  }
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'fsurdat',
              'hgrid'=>$nl_flags->{'res'},
              'sim_year'=>$nl_flags->{'sim_year'},
              'glc_nec'=>$nl_flags->{'glc_nec'});
  
  # MML: try and add my own namelist variable for mml_surdat forcing file
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'mml_surdat');
  
  
}

#-------------------------------------------------------------------------------

sub setup_logic_initial_conditions {
  # Initial conditions
  # The initial date is an attribute in the defaults file which should be matched unless
  # the user explicitly requests to ignore the initial date via the -ignore_ic_date option,
  # or just ignore the year of the initial date via the -ignore_ic_year option.
  #
  # MUST BE AFTER: setup_logic_demand   which is where flanduse_timeseries is set
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  my $var = "finidat";
  my $finidat = $nl->get_value($var);
  if ( $nl_flags->{'clm_start_type'} =~ /cold/ ) {
    if (defined $finidat ) {
      $log->warning("setting $var (either explicitly in your user_nl_clm or by doing a hybrid or branch RUN_TYPE)\n is incomptable with using a cold start" .
              " (by setting CLM_FORCE_COLDSTART=on)." );
      $log->warning("Overridding input $var file with one specifying that this is a cold start from arbitrary initial conditions." );
      my $group = $definition->get_group_name($var);
      $nl->set_variable_value($group, $var, "' '" );
    }
    add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl,
                $var, 'val'=>"' '", 'no_abspath'=>1);
    $finidat = $nl->get_value($var);
  } elsif ( defined $finidat ) {
    if ( string_is_undef_or_empty($finidat) ) {
      print "You are setting $var to blank which signals arbitrary initial conditions.\n";
      print "But, CLM_FORCE_COLDSTART is off which is a contradiction. For arbitrary initial conditions just use the CLM_FORCE_COLDSTART option\n";
      $log->fatal_error("To do a cold-start set ./xmlchange CLM_FORCE_COLDSTART=on, and remove the setting of $var in the user_nl_clm file");
    }
  }
  my $useinitvar = "use_init_interp";

  if (not defined $finidat ) {
    my $ic_date = $nl->get_value('start_ymd');
    my $st_year = int( $ic_date / 10000);
    my $nofail = 1;
    my %settings;
    $settings{'hgrid'}   = $nl_flags->{'res'};
    $settings{'phys'}    = $physv->as_string();
    $settings{'nofail'}  = $nofail;
    my $fsurdat          = $nl->get_value('fsurdat');
    $fsurdat             =~ s!(.*)/!!;
    $settings{'fsurdat'} = $fsurdat;
    #
    # If not transient use sim_year, otherwise use date
    #
    if (string_is_undef_or_empty($nl->get_value('flanduse_timeseries'))) {
       $settings{'sim_year'}     = $nl_flags->{'sim_year'};
       $opts->{'ignore_ic_year'} = 1; 
    } else {
       delete( $settings{'sim_year'} );
    }
    foreach my $item ( "mask", "maxpft", "glc_nec", "use_cn", "use_cndv", 
                       "use_nitrif_denitrif", "use_vertsoilc", "use_century_decomp", 
                     ) {
       $settings{$item}    = $nl_flags->{$item};
    }
    if ($opts->{'ignore_ic_year'}) {
       $settings{'ic_md'} = $ic_date;
    } else {
       $settings{'ic_ymd'} = $ic_date;
    }
    my $try = 0;
    my $done = 2;
    my $use_init_interp_default = $nl->get_value($useinitvar);
    if ( string_is_undef_or_empty( $use_init_interp_default ) ) {
      $use_init_interp_default = ".false.";
    }
    $settings{$useinitvar} = $use_init_interp_default;
    do {
       $try++;
       add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $var, %settings );
       # If couldn't find a matching finidat file, check if can turn on interpolation and try to find one again
       $finidat = $nl->get_value($var);
       if ( not defined $finidat ) {
          # Delete any date settings
          delete( $settings{'ic_ymd'} );
          delete( $settings{'ic_md'}  );
          add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, "init_interp_sim_years" );
          add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, "init_interp_how_close" );
          foreach my $sim_yr ( split( /,/, $nl->get_value("init_interp_sim_years") )) {
             if ( abs($st_year - $sim_yr) < $nl->get_value("init_interp_how_close") ) {
                $settings{'sim_year'} = $sim_yr;
             }
          } 
          add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $useinitvar,
                     'use_cndv'=>$nl_flags->{'use_cndv'}, 'phys'=>$physv->as_string(),
                     'sim_year'=>$settings{'sim_year'}, 'nofail'=>1 );
          $settings{$useinitvar} = $nl->get_value($useinitvar);
          if ( $try > 1 ) {
             my $group = $definition->get_group_name($useinitvar);
             $nl->set_variable_value($group, $useinitvar, $use_init_interp_default );
          }
          if ( &value_is_true($nl->get_value($useinitvar) ) ) {

             add_default($opts,  $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, "init_interp_attributes",
                        'sim_year'=>$settings{'sim_year'}, 'use_cndv'=>$nl_flags->{'use_cndv'}, 
                        'glc_nec'=>$nl_flags->{'glc_nec'},
                        'use_cn'=>$nl_flags->{'use_cn'}, 'nofail'=>1 );
             my $attributes_string = remove_leading_and_trailing_quotes($nl->get_value("init_interp_attributes"));
             foreach my $pair ( split( /\s/, $attributes_string) ) {
                if ( $pair =~ /^([a-z_]+)=([a-z._0-9]+)$/ ) {
                   $settings{$1} = $2;
                } else {
                   $log->fatal_error("Problem interpreting init_interp_attributes");
                }
             }
          } else {
             if ( $nl_flags->{'clm_start_type'} =~ /startup/  ) {
                $log->fatal_error("clm_start_type is startup so an initial conditions ($var) file is required, but can't find one without $useinitvar being set to true");
             }
             $try = $done;
          }
       } else {
         $try = $done
       }
    } while( ($try < $done) && (not defined $finidat ) );
    if ( not defined $finidat  ) {
      my $group = $definition->get_group_name($var);
      $nl->set_variable_value($group, $var, "' '" );
    }
  }
  $finidat = $nl->get_value($var);
  if ( &value_is_true($nl->get_value($useinitvar) ) && string_is_undef_or_empty($finidat) ) {
     $log->fatal_error("$useinitvar is set BUT $var is NOT, need to set both" );
  }
} # end initial conditions

#-------------------------------------------------------------------------------

sub setup_logic_bgc_shared {
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  if ( $nl_flags->{'bgc_mode'} ne "sp" ) {
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'constrain_stress_deciduous_onset', 'phys'=>$physv->as_string() );
  }
}

#-------------------------------------------------------------------------------

sub setup_logic_hydrology_switches {
  #
  # Check on Switches for hydrology
  #
  my ($nl, $physv) = @_;

  my $subgrid    = $nl->get_value('subgridflag' );
  my $origflag   = $nl->get_value('origflag'    );
  my $h2osfcflag = $nl->get_value('h2osfcflag'  );
  if ( $origflag == 1 && $subgrid == 1 ) {
    $log->fatal_error("if origflag is ON, subgridflag can NOT also be on!");
  }
  if ( $h2osfcflag == 1 && $subgrid != 1 ) {
    $log->fatal_error("if h2osfcflag is ON, subgridflag can NOT be off!");
  }
  # These should NOT be set for CLM5.0 and beyond
  if ( $physv->as_long() > $physv->as_long("clm4_5") ) {
     foreach my $var ( "origflag", "h2osfcflag", "oldfflag" ) {
        my $val = $nl->get_value($var);
        if ( defined($val) ) {
           $log->fatal_error( "ERROR:: $var=$val is deprecated and can only be used with CLM4.5" );
        }
     }
  }
  # Test bad configurations
  my $lower   = $nl->get_value( 'lower_boundary_condition'  );
  my $use_bed = $nl->get_value( 'use_bedrock'               );
  my $soilmtd = $nl->get_value( 'soilwater_movement_method' );
  if ( defined($soilmtd) && defined($lower) && $soilmtd == 0 && $lower != 4 ) {
      $log->fatal_error( "If soil water movement method is zeng-decker -- lower_boundary_condition can only be aquifer" );
  }
  if ( defined($soilmtd) && defined($lower) && $soilmtd == 1 && $lower == 4 ) {
      $log->fatal_error( "If soil water movement method is adaptive -- lower_boundary_condition can NOT be aquifer" );
  }
  if ( defined($use_bed) && defined($lower) && (&value_is_true($use_bed)) && $lower != 2 ) {
     $log->fatal_error( "If use_bedrock is on -- lower_boundary_condition can only be flux" );
  }
  if ( defined($h2osfcflag) && defined($lower) && $h2osfcflag == 0 && $lower != 4 ) {
     $log->fatal_error( "If h2osfcflag is 0 lower_boundary_condition can only be aquifer" );
  }
}

#-------------------------------------------------------------------------------

sub setup_logic_dynamic_plant_nitrogen_alloc {
  #
  # dynamic plant nitrogen allocation model, bgc=bgc
  #
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  if ( &value_is_true($nl_flags->{'use_cn'}) ) {
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'use_flexibleCN',
                'phys'=>$physv->as_string(), 'use_cn'=>$nl_flags->{'use_cn'} );
    $nl_flags->{'use_flexibleCN'} = $nl->get_value('use_flexibleCN');

    if ( &value_is_true($nl_flags->{'use_flexibleCN'}) ) {
      # TODO(bja, 2015-04) make this depend on > clm 5.0 and bgc mode at some point.
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'MM_Nuptake_opt',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'downreg_opt',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'plant_ndemand_opt',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'substrate_term_opt',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'nscalar_opt',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'temp_scalar_opt',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'CNratio_floating',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'reduce_dayl_factor',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'vcmax_opt',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'CN_residual_opt',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'CN_partition_opt',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'CN_evergreen_phenology_opt',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'} );
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'carbon_resp_opt',
                  'use_flexibleCN'=>$nl_flags->{'use_flexibleCN'}, 'use_fun'=>$nl->get_value('use_fun') );
      if ( $nl->get_value('carbon_resp_opt') == 1 && &value_is_true($nl->get_value('use_fun')) ) {
        $log->fatal_error("carbon_resp_opt should NOT be set to 1 when FUN is also on");
      }
    }
  } elsif ( ! &value_is_true($nl_flags->{'use_cn'}) ) {
     if ( &value_is_true($nl->get_value('use_flexibleCN')) ) {
        $log->fatal_error("use_flexibleCN can ONLY be set if CN is on");
     }
  }
}

#-------------------------------------------------------------------------------

sub setup_logic_hydrstress {
  #
  # Plant hydraulic stress model
  #
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  # TODO(kwo, 2015-09) make this depend on > clm 5.0 at some point.
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'use_hydrstress' );
  $nl_flags->{'use_hydrstress'} = $nl->get_value('use_hydrstress');
}

#-------------------------------------------------------------------------------

sub setup_logic_dynamic_roots {
  #
  # dynamic root model
  #
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'use_dynroot', 'phys'=>$physv->as_string(), 'bgc_mode'=>$nl_flags->{'bgc_mode'});
  my $use_dynroot = $nl->get_value('use_dynroot');
  if ( &value_is_true($use_dynroot) && ($nl_flags->{'bgc_mode'} eq "sp") ) {
    $log->fatal_error("Cannot turn dynroot mode on mode bgc=sp\n" .
                "Set the bgc mode to 'cn' or 'bgc'.");
  }
  if ( &value_is_true( $use_dynroot ) && &value_is_true( $nl_flags->{'use_hydrstress'} ) ) {
     $log->fatal_error("Cannot turn use_dynroot on when use_hydrstress is on" );
  }
}

#-------------------------------------------------------------------------------

sub setup_logic_canopy {
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;
  #
  # Canopy state
  #
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults,
              $nl, 'leaf_mr_vcm', 'phys'=>$nl_flags->{'phys'} )
}

#-------------------------------------------------------------------------------

sub setup_logic_soilwater_movement {
  # soilwater_movement require clm4_5/clm5_0
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'soilwater_movement_method' );
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'upper_boundary_condition' );

  my $soilmtd = $nl->get_value("soilwater_movement_method");
  my $use_bed = $nl->get_value('use_bedrock'              );
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 
  'lower_boundary_condition', 
  'soilwater_movement_method'=>$soilmtd, 'use_bedrock'=>$use_bed
 );
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'dtmin' );
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'verySmall' );
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'xTolerUpper' );
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'xTolerLower' );
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'expensive' );
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'inexpensive' );
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'flux_calculation' );
}
#-------------------------------------------------------------------------------

sub setup_logic_cnvegcarbonstate {
  #  MUST be AFTER: setup_logic_dynamic_plant_nitrogen_alloc as depends on mm_nuptake_opt which is set there
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  if ( &value_is_true($nl->get_value('use_cn')) ) {
    my $mmnuptake = $nl->get_value('mm_nuptake_opt');
    if ( ! defined($mmnuptake) ) { $mmnuptake = ".false."; }
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'initial_vegC', 
                'use_cn' => $nl->get_value('use_cn'), 'mm_nuptake_opt' => $mmnuptake );
  }
}

#-------------------------------------------------------------------------------

sub setup_logic_rooting_profile {
  #
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'rooting_profile_method_water' );
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'rooting_profile_method_carbon' );
}

#-------------------------------------------------------------------------------

sub setup_logic_soil_resis {
  #
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'soil_resis_method' );
}

#-------------------------------------------------------------------------------

sub setup_logic_canopyhydrology {
  #
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'interception_fraction' );
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'maximum_leaf_wetted_fraction' );
  add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'use_clm5_fpi' );
}

#-------------------------------------------------------------------------------

sub setup_logic_snowpack {
  #
  # Snowpack related options
  #
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  if ($physv->as_long() >= $physv->as_long("clm4_5")) {
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'nlevsno');
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'h2osno_max');
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'int_snow_max');
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'n_melt_glcmec');
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'wind_dependent_snow_density');
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'snow_overburden_compaction_method');
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'lotmp_snowdensity_method');
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'upplim_destruct_metamorph');
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'fresh_snw_rds_max');
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'reset_snow');
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'reset_snow_glc');
    add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'reset_snow_glc_ela');

    if (remove_leading_and_trailing_quotes($nl->get_value('snow_overburden_compaction_method')) eq 'Vionnet2012') {
       # overburden_compress_tfactor isn't used if we're using the Vionnet2012
       # snow overburden compaction method, so make sure the user hasn't tried
       # to set it
       if (defined($nl->get_value('overburden_compress_tfactor'))) {
          $log->fatal_error('overburden_compress_tfactor is set, but does not apply when using snow_overburden_compaction_method=Vionnet2012');
       }
    } else {
       add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'overburden_compress_tfactor');
    }
  }
}

#-------------------------------------------------------------------------------

sub setup_logic_atm_forcing {
   #
   # Options related to atmospheric forcings
   #
   my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

   if ($physv->as_long() >= $physv->as_long("clm4_5")) {
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'glcmec_downscale_longwave');
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'repartition_rain_snow');
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'lapse_rate');

      my $var;

      foreach $var ("lapse_rate_longwave",
                    "longwave_downscaling_limit") {
         if ( &value_is_true($nl->get_value("glcmec_downscale_longwave")) ) {
            add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $var);
         } else {
            if (defined($nl->get_value($var))) {
               $log->fatal_error("$var can only be set if glcmec_downscale_longwave is true");
            }
         }
      }

      foreach $var ("precip_repartition_glc_all_snow_t",
                    "precip_repartition_glc_all_rain_t",
                    "precip_repartition_nonglc_all_snow_t",
                    "precip_repartition_nonglc_all_rain_t") {
         if ( &value_is_true($nl->get_value("repartition_rain_snow")) ){
            add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, $var);
         } else {
            if (defined($nl->get_value($var))) {
               $log->fatal_error("$var can only be set if repartition_rain_snow is true");
            }
         }
      }
   }
}

#-------------------------------------------------------------------------------

sub setup_logic_lnd2atm {
   #
   # Options related to fields sent to atmosphere
   #
   my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

   if ($physv->as_long() >= $physv->as_long("clm4_5")) {
      add_default($opts, $nl_flags->{'inputdata_rootdir'}, $definition, $defaults, $nl, 'melt_non_icesheet_ice_runoff');
   }
}

#-------------------------------------------------------------------------------

sub write_output_files {
  my ($opts, $nl_flags, $defaults, $nl, $physv) = @_;

  my $note = "";
  my $var = "note";
  if ( ! defined($opts->{$var}) ) {
    $opts->{$var} = $defaults->get_value($var);
  }
  if ( $opts->{$var} ) {
    $note = "Comment:\n" .
      "This namelist was created using the following command-line:\n" .
        "    $nl_flags->{'cfgdir'}/$ProgName $nl_flags->{'cmdline'}\n" .
          "For help on options use: $nl_flags->{'cfgdir'}/$ProgName -help";
  }

  # CLM component
  my @groups = qw(clm_inparm 
                 lai_streams atm2lnd_inparm lnd2atm_inparm 
                 cnvegcarbonstate
                 finidat_consistency_checks 
                 clm_initinterp_inparm 
                 soilwater_movement_inparm rooting_profile_inparm
                 soil_resis_inparm bgc_shared 
                 clmu_inparm clm_soilstate_inparm 
                 clm_soilhydrology_inparm
                 clm_glacier_behavior);

 if ( $physv->as_long() >= $physv->as_long("clm4_5") ) {
   push @groups, "cn_general";
   push @groups, "clm_canopy_inparm";
 }

  my $outfile;
  $outfile = "$opts->{'dir'}/lnd_in";
  $nl->write($outfile, 'groups'=>\@groups, 'note'=>"$note" );
  $log->verbose_message("Writing clm namelist to $outfile");
}

sub write_output_real_parameter_file {
  my ($opts, $nl_flags, $definition, $defaults, $nl, $physv) = @_;

  # Output real parameters
  if ( defined($opts->{'output_reals_filename'}) ) {
     my $file = $opts->{'output_reals_filename'};
     my $fh = IO::File->new($file, '>>') or $log->fatal_error("can't create real parameter filename: $file");
     foreach my $var ( $definition->get_var_names() ) {
        my $type = $definition->get_var_type($var);
        my $doc  = $definition->get_var_doc($var);
        $doc =~ s/\n//g;
        if ( $type =~ /real/ ) {
           my $val = $nl->get_value($var);
           if ( ! defined($val) ) { $val = "?.??"; }
           print $fh "\! $doc\n$var = $val\n";
        }
     }
     $fh->close();
  }
}

#-------------------------------------------------------------------------------

sub add_default {

# Add a value for the specified variable to the specified namelist object.  The variables
# already in the object have the higher precedence, so if the specified variable is already
# defined in the object then don't overwrite it, just return.
#
# This method checks the definition file and adds the variable to the correct
# namelist group.
#
# The value can be provided by using the optional argument key 'val' in the
# calling list.  Otherwise a default value is obtained from the namelist
# defaults object.  If no default value is found this method throws an exception
# unless the 'nofail' option is set true.
#
# Example 1: Specify the default value $val for the namelist variable $var in namelist
#            object $nl:
#
#  add_default($inputdata_rootdir, $definition, $defaults, $nl, $var, 'val'=>$val)
#
# Example 2: Add a default for variable $var if an appropriate value is found.  Otherwise
#            don't add the variable
#
#  add_default($inputdata_rootdir, $definition, $defaults, $nl, $var, 'nofail'=>1)
#
#
# ***** N.B. ***** This routine assumes the following variables are in package main::
#  $definition        -- the namelist definition object
#  $defaults          -- the namelist defaults object
#  $inputdata_rootdir -- CESM inputdata root directory

  my $opts = shift;
  my $inputdata_rootdir = shift;
  my $definition = shift;
  my $defaults = shift;
  my $nl = shift;
  my $var = shift;
  my %settings = @_;

  my $test_files = $opts->{'test'};
  #my $nl = shift;     # namelist object
  #my $var = shift;    # name of namelist variable
  #my %settings = @_;      # options

  # If variable has quotes around it
  if ( $var =~ /'(.+)'/ ) {
    $var = $1;
  }
  # Query the definition to find which group the variable belongs to.  Exit if not found.

  my $group = $definition->get_group_name($var);
  unless ($group) {
    my $fname = $definition->get_file_name();
    $log->fatal_error("variable \"$var\" not found in namelist definition file $fname.");
  }

  # check whether the variable has a value in the namelist object -- if so then skip to end
  my $val = $nl->get_variable_value($group, $var);
  if (! defined $val) {

    # Look for a specified value in the options hash

    if (defined $settings{'val'}) {
      $val = $settings{'val'};
    }
    # or else get a value from namelist defaults object.
    # Note that if the 'val' key isn't in the hash, then just pass anything else
    # in %settings to the get_value method to be used as attributes that are matched
    # when looking for default values.
    else {

      $val = $defaults->get_value($var, \%settings);

      # Truncate model_version appropriately

      if ( $var eq "model_version" ) {
        $val =~ /(URL: https:\/\/[a-zA-Z0-9._-]+\/)([a-zA-Z0-9\/._-]+)(\/bld\/.+)/;
        $val = $2;
      }
    }

    # if no value is found then exit w/ error (unless 'nofail' option set)
    unless ( defined($val) ) {
      unless ($settings{'nofail'}) {
        if ($var eq 'finidat') {
          $log->message("No default value found for $var.\n" .
                  "            Are defaults provided for this resolution and land mask?" );
        } else {
          $log->fatal_error("No default value found for $var.\n" .
                      "            Are defaults provided for this resolution and land mask?");
        }
      }
      else {
        return;
      }
    }

    # query the definition to find out if the variable is an input pathname
    my $is_input_pathname = $definition->is_input_pathname($var);

    # The default values for input pathnames are relative.  If the namelist
    # variable is defined to be an absolute pathname, then prepend
    # the CESM inputdata root directory.
    if (not defined $settings{'no_abspath'}) {
      if (defined $settings{'set_abspath'}) {
        $val = set_abs_filepath($val, $settings{'set_abspath'});
      } else {
        if ($is_input_pathname eq 'abs') {
          $val = set_abs_filepath($val, $inputdata_rootdir);
          if ( $test_files and ($val !~ /null/) and (! -f "$val") ) {
            $log->fatal_error("file not found: $var = $val");
          }
        }
      }
    }

    # query the definition to find out if the variable takes a string value.
    # The returned string length will be >0 if $var is a string, and 0 if not.
    my $str_len = $definition->get_str_len($var);

    # If the variable is a string, then add quotes if they're missing
    if ($str_len > 0) {
      $val = quote_string($val);
    }

    # set the value in the namelist
    $nl->set_variable_value($group, $var, $val);
  }

}

#-------------------------------------------------------------------------------

sub expand_xml_variables_in_namelist {
   # Go through all variables in the namelist and expand any XML env settings in them
   my ($nl, $xmlvar_ref) = @_;

   foreach my $group ( $nl->get_group_names() ) {
       foreach my $var ( $nl->get_variable_names($group) ) {
          my $val    = $nl->get_variable_value($group, $var);
          my $newval = SetupTools::expand_xml_var( $val, $xmlvar_ref );
          if ( $newval ne $val ) {
             $nl->set_variable_value($group, $var, $newval);
          }
       }
   }
}

#-------------------------------------------------------------------------------

sub check_input_files {

# For each variable in the namelist which is an input dataset, check to see if it
# exists locally.
#
# ***** N.B. ***** This routine assumes the following variables are in package main::
#  $definition        -- the namelist definition object
#  $nl                -- namelist object
#  $inputdata_rootdir -- if false prints test, else creates inputdata file

    my ($nl, $inputdata_rootdir, $outfile, $definition) = @_;

    open(OUTFILE, ">>$outfile") if defined $inputdata_rootdir;

    # Look through all namelist groups
    my @groups = $nl->get_group_names();
    foreach my $group (@groups) {

        # Look through all variables in each group
        my @vars = $nl->get_variable_names($group);
        foreach my $var (@vars) {

            # Is the variable an input dataset?
            my $input_pathname_type = $definition->is_input_pathname($var);

            # If it is, check whether it exists locally and print status
            if ($input_pathname_type) {

                # Get pathname of input dataset
                my $pathname = $nl->get_variable_value($group, $var);
                # Need to strip the quotes
                $pathname =~ s/['"]//g;

                if ($input_pathname_type eq 'abs') {
                    if ($inputdata_rootdir) {
                        #MV $pathname =~ s:$inputdata_rootdir::;
                        print OUTFILE "$var = $pathname\n";
                    }
                    else {
                        if (-e $pathname) {  # use -e rather than -f since the absolute pathname
                                             # might be a directory
                            print "OK -- found $var = $pathname\n";
                        }
                        else {
                            print "NOT FOUND:  $var = $pathname\n";
                        }
                    }
                }
                elsif ($input_pathname_type =~ m/rel:(.+)/o) {
                    # The match provides the namelist variable that contains the
                    # root directory for a relative filename
                    my $rootdir_var = $1;
                    my $rootdir = $nl->get_variable_value($group, $rootdir_var);
                    $rootdir =~ s/['"]//g;
                    if ($inputdata_rootdir) {
                        $pathname = "$rootdir/$pathname";
                        #MV $pathname =~ s:$inputdata_rootdir::;
                        print OUTFILE "$var = $pathname\n";
                    }
                    else {
                        if (-f "$rootdir/$pathname") {
                            print "OK -- found $var = $rootdir/$pathname\n";
                        }
                        else {
                            print "NOT FOUND:  $var = $rootdir/$pathname\n";
                        }
                    }
                }
            }
        }
    }
    close OUTFILE if defined $inputdata_rootdir;
    return 0 if defined $inputdata_rootdir;
}

#-------------------------------------------------------------------------------

sub set_abs_filepath {

# check whether the input filepath is an absolute path, and if it isn't then
# prepend a root directory

    my ($filepath, $rootdir) = @_;

    # strip any leading/trailing whitespace and quotes
    $filepath = trim($filepath);
    $filepath = remove_leading_and_trailing_quotes($filepath);
    $rootdir  = trim($rootdir);
    $rootdir = remove_leading_and_trailing_quotes($rootdir);

    my $out = $filepath;
    unless ( $filepath =~ /^\// ) {  # unless $filepath starts with a /
        $out = "$rootdir/$filepath"; # prepend the root directory
    }
    return $out;
}

#-------------------------------------------------------------------------------

sub valid_option {

    my ($val, @expect) = @_;

    my $expect;

    $val = trim($val);

    foreach $expect (@expect) {
        if ($val =~ /^$expect$/i) { return $expect; }
    }
    return undef;
}

#-------------------------------------------------------------------------------

sub check_use_case_name {
#
# Check the use-case name and ensure it follows the naming convention.
#
  my ($use_case) = @_;

  my $diestring = "bad use_case name $use_case, follow the conventions " .
                  "in namelist_files/use_cases/README\n";
  my $desc = "[a-zA-Z0-9]*";
  my $rcp  = "rcp[0-9\.]+";
  if (      $use_case =~ /^[0-9]+-[0-9]+([a-zA-Z0-9_\.]*)_transient$/ ) {
    my $string = $1;
    if (      $string =~ /^_($rcp)_*($desc)$/ ) {
       # valid name
    } elsif ( $string =~ /^_*($desc)$/ ) {
       # valid name
    } else {
      $log->fatal_error($diestring);
    }
  } elsif ( $use_case =~ /^20thC([a-zA-Z0-9_\.]*)_transient$/ ) {
    my $string = $1;
    if (      $string =~ /^_($rcp)_*($desc)$/ ) {
       # valid name
    } elsif ( $string =~ /^_*($desc)$/ ) {
       # valid name
    } else {
      $log->fatal_error($diestring);
    }
  } elsif ( $use_case =~ /^([0-9]+)_*($desc)_control$/   ) {
     # valid name
  } elsif ( $use_case =~ /^($desc)_pd$/   ) {
     # valid name
  } else {
      $log->fatal_error($diestring);
  }
}

#-------------------------------------------------------------------------------

sub validate_options {

# $source -- text string declaring the source of the options being validated
# $cfg    -- configure object
# $opts   -- reference to hash that contains the options

    my ($source, $cfg, $opts) = @_;

    my ($opt, $old, @expect);

    # use_case
    $opt = 'use_case';
    if (defined $opts->{$opt}) {

        if ( $opts->{$opt} ne "list" ) {
           # create the @expect array by listing the files in $use_case_dir
           # and strip off the ".xml" part of the filename
           @expect = ();
           my @files = glob("$opts->{'use_case_dir'}/*.xml");
           foreach my $file (@files) {
               $file =~ m{.*/(.*)\.xml};
               &check_use_case_name( $1 );
               push @expect, $1;
           }

           $old = $opts->{$opt};
           $opts->{$opt} = valid_option($old, @expect)
               or $log->fatal_error("invalid value of $opt ($old) specified in $source\n" .
                              "expected one of: @expect");
        } else {
           print "Use cases are:...\n\n";
           my @ucases;
           foreach my $file( sort( glob($opts->{'use_case_dir'}."/*.xml") ) ) {
              my $use_case;
              if ( $file =~ /\/([^\/]+)\.xml$/ ) {
                 &check_use_case_name( $1 );
                 $use_case = $1;
              } else {
                 $log->fatal_error("Bad name for use case file = $file");
              }
              my $uc_defaults = Build::NamelistDefaults->new("$file", $cfg);
              printf "%15s = %s\n", $use_case, $uc_defaults->get_value("use_case_desc");
              push @ucases, $use_case;
           }
           $log->exit_message("use cases : @ucases");
        }
    }
}

#-------------------------------------------------------------------------------

sub list_options {
#
# List the options for different command line values if asked for
#
    my ($opts_cmdl, $definition, $defaults) = @_;

    # options to list values that are in the defaults files
    my @opts_list = ( "res", "mask", "sim_year", "rcp" );
    my %opts_local;
    foreach my $var ( "res", "mask", "sim_year", "rcp" ) {
       my $val;
       if (      $opts_cmdl->{$var} eq "list" ) {
         $val = "default";
       } elsif ( $opts_cmdl->{$var} eq "default" ) {
         $val = $defaults->get_value($var, \%opts_local );
       } else {
         $val = $opts_cmdl->{$var};
       }
       my $vname = $var;
       if ( $vname eq "res" ) { $vname = "hgrid"; }
       $opts_local{$vname} = $val;
    }
    foreach my $var ( @opts_list ) {
       if (defined $opts_cmdl->{$var}) {

           if ( $opts_cmdl->{$var} eq "list" ) {
               my @valid_values   = $definition->get_valid_values( $var );
               if ( $var eq "sim_year" ) {
                   unshift( @valid_values,
                            $definition->get_valid_values( "sim_year_range" ) );
               }
               unshift( @valid_values, "default" );
               # Strip out quotes and the constant value
               for( my $i = 0; $i <= $#valid_values; $i++ ) {
                  $valid_values[$i] =~ s/('|')//g;
                  if ( $valid_values[$i] eq "constant" ) { $valid_values[$i] = undef; }
               }
               my $val= $defaults->get_value($var, \%opts_local);
               my $doc = $definition->get_var_doc( $var );
               $doc =~ s/\n//;
               chomp( $doc );
               $log->exit_message("valid values for $var ($doc) :\n" .
                            "    Values: @valid_values\n" .
                            "    Default = $val\n" .
                            "    (NOTE: resolution and mask and other settings may influence what the default is)");
           }
       }
    }
    # clm_demand
    my $var = 'clm_demand';
    if (defined $opts_cmdl->{$var}) {

        if ( $opts_cmdl->{$var} eq "list" ) {
           my @vars = $definition->get_var_names( );
           my @demands = ( "null" );
           foreach my $var ( @vars ) {
              if ( $definition->get_group_name( $var ) ne "clm_inparm" ) { next; }
              if ( defined($defaults->get_value($var, $opts_cmdl ) ) ) {
                 push( @demands, $var );
              }
           }
           my $doc = $definition->get_var_doc( 'clm_demand' );
           $doc =~ s/\n//;
           chomp( $doc );
           $log->exit_message("valid values for $var ($doc) :\n" .
                        "Namelist options to require: @demands\n" .
                        "any valid namelist item for clm_inparm can be set. However, not all are\n" .
                        "available in the clm defaults file. The defaults are also dependent on\n" .
                        "resolution and landmask, as well as other settings. Hence, the list above\n" .
                        "will vary depending on what you set for resolution and landmask.");
        }
    }
}

#-------------------------------------------------------------------------------

sub trim {
   # remove leading and trailing whitespace from a string.
   my ($str) = @_;
   $str =~ s/^\s+//;
   $str =~ s/\s+$//;
   return $str;
}

#-------------------------------------------------------------------------------

sub quote_string {
   # Add quotes around a string, unless they are already there
   my ($str) = @_;
   $str = trim($str);
   unless ($str =~ /^['"]/) {        #"'
      $str = "\'$str\'";
   }
   return $str;
 }

#-------------------------------------------------------------------------------

sub remove_leading_and_trailing_quotes {
   # Remove leading and trailing single and double quotes from a string. Also
   # removes leading spaces before the leading quotes, and trailing spaces after
   # the trailing quotes.

   my ($str) = @_;

   $str = trim($str);

   # strip any leading/trailing quotes
   $str =~ s/^['"]+//;
   $str =~ s/["']+$//;

   return $str;
}

#-------------------------------------------------------------------------------

sub logical_to_fortran {
   # Given a logical variable ('true' / 'false'), convert it to a fortran-style logical ('.true.' / '.false.')
   # The result will be lowercase, regardless of the case of the input.
   my ($var) = @_;
   my $result;

   if (lc($var) eq 'true') {
      $result = ".true.";
   }
   elsif (lc($var) eq 'false') {
      $result = ".false.";
   }
   else {
      $log->fatal_error("Unexpected value in logical_to_fortran: $var");
   }

   return $result;
}

#-------------------------------------------------------------------------------

sub string_is_undef_or_empty {
   # Return true if the given string is undefined or only spaces, false otherwise.
   # A quoted empty string (' ' or " ") is treated as being empty.
   my ($str) = @_;
   if (!defined($str)) {
      return 1;
   }
   else {
      $str = remove_leading_and_trailing_quotes($str);
      if ($str =~ /^\s*$/) {
         return 1;
      }
      else {
         return 0;
      }
   }
}

#-------------------------------------------------------------------------------

sub value_is_true {
   # Return true if the given namelist value is .true.
   # An undefined value is treated as false (with the assumption that false is the default in the code)
   my ($val) = @_;

   # Some regular expressions...
   ###my $TRUE  = qr/\.true\./i;
   ###my $FALSE = qr/\.false\./i;
   # **N.B.** the use of qr// for precompiling regexps isn't supported until perl 5.005.
   my $TRUE  = '\.?true\.?|[t]';
   my $FALSE = '\.?false\.?|[f]';
   my $is_true = 0;
   if (defined($val)) {
      if ($val =~ /$TRUE/i) {
         $is_true = 1;
      }
   }

   return $is_true;
}

#-------------------------------------------------------------------------------

sub version {
# The version is found in CLM ChangeLog file.
# $cfgdir is set by the configure script to the name of its directory.

    my ($cfgdir) = @_;

    my $logfile = "$cfgdir/../doc/ChangeLog";

    my $fh = IO::File->new($logfile, '<') or $log->fatal_error("can't open ChangeLog file: $logfile");

    while (my $line = <$fh>) {

        if ($line =~ /^Tag name:\s*([a-zA-Z0-9_. -]*[clmcesm0-9_.-]+)$/ ) {
            $log->exit_message("$1");
        }
    }
}

#-------------------------------------------------------------------------------

sub main {
  my %nl_flags;
  $nl_flags{'cfgdir'} = dirname(abs_path($0));

  my %opts = process_commandline(\%nl_flags);
  my $cfgdir = $nl_flags{'cfgdir'};
  check_for_perl_utils($cfgdir, \%opts);

  $log     = namelist_files::LogMessages->new( $ProgName, \%opts );   # global
  version($cfgdir) if $opts{'version'};
  my $cfg = read_configure_definition($cfgdir, \%opts);

  my $physv      = config_files::clm_phys_vers->new( $cfg->get('phys') );
  my $definition = read_namelist_definition($cfgdir, \%opts, \%nl_flags, $physv);
  my $defaults   = read_namelist_defaults($cfgdir, \%opts, \%nl_flags, $cfg, $physv);

  # List valid values if asked for
  list_options(\%opts, $definition, $defaults);

  # Validate some of the commandline option values.
  validate_options("commandline", $cfg, \%opts);

  # Create an empty namelist object.
  my $nl = Build::Namelist->new();

  check_cesm_inputdata(\%opts, \%nl_flags);

  # Read in the env_*.xml files
  my %env_xml    = read_envxml_case_files( \%opts );

  # Process the user inputs
  process_namelist_user_input(\%opts, \%nl_flags, $definition, $defaults, $nl, $cfg, \%env_xml, $physv );
  # Get any other defaults needed from the namelist defaults file
  process_namelist_inline_logic(\%opts, \%nl_flags, $definition, $defaults, $nl, $cfg, \%env_xml, $physv);

  # Validate that the entire resultant namelist is valid
  $definition->validate($nl);
  write_output_files(\%opts, \%nl_flags, $defaults, $nl, $physv);
  write_output_real_parameter_file(\%opts, \%nl_flags, $definition, $defaults, $nl, $physv);

  if ($opts{'inputdata'}) {
    check_input_files($nl, $nl_flags{'inputdata_rootdir'}, $opts{'inputdata'}, $definition);
  }
  $log->final_exit("Successfully made CLM namelist file");
}

#-------------------------------------------------------------------------------

1;
