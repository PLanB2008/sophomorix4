#!/usr/bin/perl -w
# This perl module SophomorixSambaAD is maintained by Rüdiger Beck
# It is Free Software (License GPLv3)
# If you find errors, contact the author
# jeffbeck@web.de  or  jeffbeck@linuxmuster.net

package Sophomorix::SophomorixSambaAD;
require Exporter;
#use File::Basename;
#use Time::Local;
#use Time::localtime;
#use Quota;
#use Sys::Filesystem ();
use Unicode::Map8;
use Unicode::String qw(utf16);
use Net::LDAP;
#use Sophomorix::SophomorixBase;
use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Useqq = 1;
$Data::Dumper::Terse = 1; 

@ISA = qw(Exporter);

@EXPORT_OK = qw( );
@EXPORT = qw(
            AD_bind_admin
            AD_unbind_admin
            AD_user_create
            AD_workstation_create
            AD_user_move
            AD_user_kill
            AD_group_create
            AD_group_kill
            AD_group_addmember
            AD_group_removemember
            AD_get_ou_tokened
            AD_get_name_tokened
            get_forbidden_logins
            AD_ou_add
            AD_object_search
            AD_workstation_fetch
            AD_object_move
            AD_debug_logdump
            );

sub AD_get_passwd {
    my $smb_pwd="";
    if (-e $DevelConf::file_samba_pwd) {
        open (SECRET, $DevelConf::file_samba_pwd);
        while(<SECRET>){
            $smb_pwd=$_;
            chomp($smb_pwd);
        }
        close(SECRET);
    } else {
        print "Password of samba Administrator must ",
               "be in $DevelConf::file_samba_pwd\n";
        exit;
    }
    return($smb_pwd);
}


sub AD_bind_admin {
    my ($smb_pwd)=&AD_get_passwd();
    my $host="ldaps://localhost";
    # check connection to Samba4 AD
    if($Conf::log_level>=3){
        print "   Checking Samba4 AD connection ...\n";
    }

    #my $ldap = Net::LDAP->new('ldaps://localhost')  or  die "$@";
    my $ldap = Net::LDAP->new($host)  or  
         &Sophomorix::SophomorixBase::log_script_exit(
                            "No connection to Samba4 AD!",
         1,1,0,@arguments);

    if($Conf::log_level>=2){
        print "Retrieving RootDSE...\n";
    }
    my $dse = $ldap->root_dse();
    # get naming Contexts
    my @contexts = $dse->get_value('namingContexts');

    ## get supported LDAP versions as an array reference
    #my $versions = $dse->get_value('supportedLDAPVersion', asref => 1);
    my $root_dse=$contexts[0];
    if($Conf::log_level>=3){
        foreach my $context (@contexts){
            print "      * NamingContext: <$context>\n";
        }
    }

    if($Conf::log_level>=2){
        print "   * RootDSE: $root_dse\n";
    }

    # admin bind
    my $admin_dn="CN=Administrator,CN=Users,".$root_dse;
    my $mesg = $ldap->bind($admin_dn, password => $smb_pwd);
    # show errors from bind
    $mesg->code && die $mesg->error;

    return ($ldap,$root_dse);
}



sub AD_unbind_admin {
    my ($ldap) = @_;
    my $mesg = $ldap->unbind();
    #  show errors from unbind
    $mesg->code && die $mesg->error;
}



sub AD_user_kill {
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
    my $root_dse = $arg_ref->{root_dse};
    my $user = $arg_ref->{login};
    my $identifier = $arg_ref->{identifier};
    my $user_count = $arg_ref->{user_count};

    &Sophomorix::SophomorixBase::print_title("Killing User $user ($user_count):");
    my ($count,$dn_exist,$cn_exist)=&AD_object_search($ldap,$root_dse,"user",$user);
    if ($count > 0){
        my $command="samba-tool user delete ". $user;
        print "   # $command\n";
        system($command);
        return;
    } else {
        print "   * User $user nonexisting ($count results)\n";
        return;
    }
}



sub AD_group_kill {
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
    my $root_dse = $arg_ref->{root_dse};
    my $group = $arg_ref->{group};
    my $type = $arg_ref->{type};

    &Sophomorix::SophomorixBase::print_title("Killing Group($type) $group:");
    my ($count,$dn_exist,$cn_exist)=&AD_object_search($ldap,$root_dse,"group",$group);
    if ($count > 0){
        my $command="samba-tool group delete ". $group;
        print "   # $command\n";
        system($command);
        return;
    } else {
        print "   * Group $group nonexisting ($count results)\n";
        return;
    }
}

sub AD_workstation_create {
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
    my $root_dse = $arg_ref->{root_dse};
    my $name = $arg_ref->{name};
    my $room = $arg_ref->{room};
    my $role = $arg_ref->{role};
    my $ws_count = $arg_ref->{ws_count};
    my $ou = $arg_ref->{ou};
    my $school_token = $arg_ref->{school_token};
    my $creationdate = $arg_ref->{creationdate};

    # calculation
    # make name uppercase
    my $name_uppercase=$name;
    $name_uppercase=~tr/a-z/A-Z/;

    # make school-token uppercase
    my $school_token_uppercase=$school_token;
    $school_token_uppercase=~tr/a-z/A-Z/;


    # names with tokens
    my $room_token=&AD_get_name_tokened($room,$school_token,"roomws");
    my $name_token=&AD_get_name_tokened($name_uppercase,
                                        $school_token_uppercase,
                                        "workstation");
    my $display_name=$name_token;
    my $smb_name=$name_token."\$";

    # dns
    my @dns_part_stripped=(); # without 'DC='
    my @dns_part=split(/,/,$root_dse);
    foreach my $part (@dns_part){
        $part=~s/DC=//g;
        #print "PART: $part\n";
        push @dns_part_stripped, $part;
    }
    my $dns_name = join(".",@dns_part_stripped);
    $dns_name=$name_token.".".$dns_name;

    my @service_principal_name=("HOST/".$name_token,
                                "HOST/".$dns_name,
                                "RestrictedKrbHost/".$name_token,
                                "RestrictedKrbHost/".$dns_name,
                               );

    my $container=&AD_get_container($role,$room_token);
    my $dn_room = $container."OU=".$ou.",".$root_dse;
    my $dn = "CN=".$name_token.",".$container."OU=".$ou.",".$root_dse;

    if($Conf::log_level>=1){
        &Sophomorix::SophomorixBase::print_title(
              "Creating workstation $ws_count: $name");
        print "   DN:                    $dn\n";
        print "   DN(Parent):            $dn_room\n";
        print "   Name:                  $name_token\n";
        print "   Room:                  $room_token\n";
        print "   OU:                    $ou\n";
        print "   sAMAccountName:        $smb_name\n";
        print "   dNSHostName:           $dns_name\n";
        foreach my $entry (@service_principal_name){
            print "   servicePrincipalName:  $entry\n";
        }
        print "\n";
    }
   $ldap->add($dn_room,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    my $result = $ldap->add( $dn,
                   attr => [
                   'sAMAccountName' => $smb_name,
                   'displayName' => $display_name,
                   'dNSHostName' => $dns_name,
#                   'givenName'   => "Workstation",
#                   'sn'   => "Account",
                   'cn'   => $name_token,
                    'accountExpires' => '9223372036854775807', # means never
                   'servicePrincipalName' => \@service_principal_name,
#                   'unicodePwd' => $uni_password,
#                   'sophomorixExitAdminClass' => "unknown", 
#                   'sophomorixUnid' => $unid,
#                   'sophomorixStatus' => "U",
#                   'sophomorixAdminClass' => $group_token,    
#                   'sophomorixFirstPassword' => $plain_password, 
#                   'sophomorixFirstnameASCII' => $firstname_ascii,
#                   'sophomorixSurnameASCII'  => $surname_ascii,
                   'sophomorixRole' => "workstation",
                   'sophomorixSchoolPrefix' => $school_token,
                   'sophomorixSchoolname' => $ou,
                   'sophomorixCreationDate' => $creationdate, 
                   'userAccountControl' => '4096',
                   'instanceType' => '4',
                   'objectclass' => ['top', 'person',
                                     'organizationalPerson',
                                     'user','computer' ],
#                   'objectclass' => \@objectclass,
                           ]
                           );
    $result->code && warn "Failed to add entry: ", $result->error ;
    &AD_debug_logdump($result,2,(caller(0))[3]);
}




sub AD_user_create {
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
    my $root_dse = $arg_ref->{root_dse};
    my $user_count = $arg_ref->{user_count};
    my $identifier = $arg_ref->{identifier};
    my $login = $arg_ref->{login};
    my $group = $arg_ref->{group};
    my $firstname_ascii = $arg_ref->{firstname_ascii};
    my $surname_ascii = $arg_ref->{surname_ascii};
    my $firstname_utf8 = $arg_ref->{firstname_utf8};
    my $surname_utf8 = $arg_ref->{surname_utf8};
    my $birthdate = $arg_ref->{birthdate};
    my $plain_password = $arg_ref->{plain_password};
    my $unid = $arg_ref->{unid};
    my $wunsch_id = $arg_ref->{wunsch_id};
    my $wunsch_gid = $arg_ref->{wunsch_gid};
    my $ou = $arg_ref->{ou};
    my $school_token = $arg_ref->{school_token};
    my $role = $arg_ref->{role};
    my $type = $arg_ref->{type};
    my $creationdate = $arg_ref->{creationdate};

    # set defaults if not defined
    if (not defined $identifier){
        $identifier="---";
    }
    if (not defined $unid){
        $unid="---";
    }
    if (not defined $wunsch_id){
        $wunsch_id="---";
    }
    if (not defined $wunsch_gid){
        $wunsch_gid="---";
    }
    $ou=&AD_get_ou_tokened($ou);

    # calculate
    my $shell="/bin/false";
    my $display_name = $firstname_utf8." ".$surname_utf8;
    my $user_principal_name = $login."\@"."linuxmuster.local";
    # dn

    my $group_token=&AD_get_name_tokened($group,$school_token,$type);
    my $login_token=&AD_get_name_tokened($login,$school_token,$role);
    my $container=&AD_get_container($role,$group_token);

    my $dn_class = $container."OU=".$ou.",".$root_dse;
    my $dn = "cn=".$login_token.",".$container."OU=".$ou.",".$root_dse;
 
    # password generation
    # build the conversion map from your local character set to Unicode    
    my $charmap = Unicode::Map8->new('latin1')  or  die;
    # surround the PW with double quotes and convert it to UTF-16
    my $uni_password = $charmap->tou('"'.$plain_password.'"')->byteswap()->utf16();

    if($Conf::log_level>=1){
        print "\n";
        &Sophomorix::SophomorixBase::print_title(
              "Creating User $user_count : $login_token");
        print "   DN:                 $dn\n";
        print "   DN(Parent):         $dn_class\n";
        print "   Surname(ASCII):     $surname_ascii\n";
        print "   Surname(UTF8):      $surname_utf8\n";
        print "   Firstname(ASCII):   $firstname_ascii\n";
        print "   Firstname(UTF8):    $firstname_utf8\n";
        print "   Birthday:           $birthdate\n";
        print "   Identifier:         $identifier\n";
        print "   OU:                 $ou\n"; # Organisatinal Unit
        print "   School Token:       $school_token\n"; # Organisatinal Unit
        print "   Role(User):         $role\n";
        print "   Type(Group):        $type\n";
        print "   Group:              $group ($group_token)\n"; # lehrer oder klasse
        print "   Unix-gid:           $wunsch_gid\n"; # lehrer oder klasse
        #print "   GECOS:              $gecos\n";
        #print "   Login (to check):   $login_name_to_check\n";
        print "   Login (check OK):   $login ($login_token)\n";
        print "   Password:           $plain_password\n";
        # sophomorix stuff
        print "   Creationdate:       $creationdate\n";
        print "   Unid:               $unid\n";
        print "   Unix-id:            $wunsch_id\n";
    }

    $ldap->add($dn_class,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    my $result = $ldap->add( $dn,
                   attr => [
                   'sAMAccountName' => $login_token,
                   'givenName'   => $firstname_utf8,
                   'sn'   => $surname_utf8,
                   'displayName'   => [$display_name],
                   'userPrincipalName' => $user_principal_name,
                   'unicodePwd' => $uni_password,
                   'sophomorixExitAdminClass' => "unknown", 
                   'sophomorixUnid' => $unid,
                   'sophomorixStatus' => "U",
                   'sophomorixAdminClass' => $group_token,    
                   'sophomorixFirstPassword' => $plain_password, 
                   'sophomorixFirstnameASCII' => $firstname_ascii,
                   'sophomorixSurnameASCII'  => $surname_ascii,
                   'sophomorixRole' => $role,
                   'sophomorixSchoolPrefix' => $school_token,
                   'sophomorixSchoolname' => $ou,
                   'sophomorixCreationDate' => $creationdate, 
                   'userAccountControl' => '512',
                   'objectclass' => ['top', 'person',
                                     'organizationalPerson',
                                     'user' ],
#                   'objectclass' => \@objectclass,
                           ]
                           );
    $result->code && warn "Failed to add entry: ", $result->error ;
    &AD_debug_logdump($result,2,(caller(0))[3]);
    &Sophomorix::SophomorixBase::print_title("Creating User $user_count (end)");
}



sub AD_user_move {
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
    my $root_dse = $arg_ref->{root_dse};
    my $user = $arg_ref->{user};
    my $user_count = $arg_ref->{user_count};
    my $group_old = $arg_ref->{group_old};
    my $group_new = $arg_ref->{group_new};
    my $ou_old = $arg_ref->{ou_old};
    my $ou_new = $arg_ref->{ou_new};
    my $school_token_old = $arg_ref->{school_token_old};
    my $school_token_new = $arg_ref->{school_token_new};
    my $role_new = $arg_ref->{role};

    # calculate
    my $group_type_old;
    my $group_type_new;
    my $target_branch;
    $ou_old=&AD_get_ou_tokened($ou_old);
    $ou_new=&AD_get_ou_tokened($ou_new);

    if ($role_new eq "student"){
         $target_branch="OU=".$group_new.",OU=Students,OU=".$ou_new.",".$root_dse;
    } elsif ($role_new eq "teacher"){
         $target_branch="OU=".$group_new.",OU=Teachers,OU=".$ou_new.",".$root_dse;
    }

    # fetch the dn (where the object really is)
    my ($count,$dn,$rdn)=&AD_object_search($ldap,$root_dse,"user",$user);
    if ($count==0){
        print "\nWARNING: $user not found in ldap, skipping\n\n";
        next;
    }
    my ($count_group_old,
        $dn_group_old,
        $rdn_group_old)=&AD_object_search($ldap,$root_dse,"group",$group_old);
    if ($count_group_old==0){
        print "\nWARNING: Group $group_old not found in ldap, skipping\n\n";
        next;
    }
    if($Conf::log_level>=1){
        print "\n";
        &Sophomorix::SophomorixBase::print_title("Moving User $user ($user_count):");

        print "   DN:             $dn\n";
        print "   Target DN:      $target_branch\n";
        print "   Group (Old):    $group_old\n";
        print "   Group (New):    $group_new\n";
        print "   Role (New):     $role_new\n";
        print "   School(Old):    $school_token_old ($ou_old)\n";
        print "   School(New):    $school_token_new ($ou_new)\n";
    }

    # make sure OU and tree exists
#    if (not exists $ou_created{$ou_new}){
#         # create new ou
         &AD_ou_add($ldap,$root_dse,$ou_new,$school_token_new);
#         # remember new ou to add it only once
#         $ou_created{$ou_new}="already created";
#     }

    # make sure new group exits
    &AD_group_create({ldap=>$ldap,
                      root_dse=>$root_dse,
                      group=>$group_new,
                      ou=>$ou_new,
                      school_token=>$school_token_new,
                      type=>"adminclass",
                    });

    # update user entry
    my $mesg = $ldap->modify( $dn,
		      replace => {
                          sophomorixAdminClass => $group_new,
                          sophomorixExitAdminClass => $group_old,
                          sophomorixSchoolPrefix => $school_token_new,
                          sophomorixSchoolname => $ou_new,
                          sophomorixRole => $role_new,
                      }
               );
    &AD_debug_logdump($mesg,2,(caller(0))[3]);

    # move user membership to new group
    &AD_group_removemember({ldap => $ldap,
                            root_dse => $root_dse, 
                            group => $group_old,
                            removemember => $user,
                          });   
    &AD_group_addmember({ldap => $ldap,
                         root_dse => $root_dse, 
                         group => $group_new,
                         addmember => $user,
                       }); 

    # move the object in ldap tree
    &AD_object_move({ldap=>$ldap,
                     dn=>$dn,
                     rdn=>$rdn,
                     target_branch=>$target_branch,
                    });
    &Sophomorix::SophomorixBase::print_title("Moving User $user (end)");
}


sub AD_get_ou_tokened {
    my ($ou) = @_;
    if ($ou eq "---"){ # use default OU: SCHOOL
        # remove OU= from configured value
        my $string=$DevelConf::AD_school_ou;
        $string=~s/^OU=//;
        $ou=$string;
    }
    return $ou;
}

sub AD_get_name_tokened {
    # $role is: group type / user role
    # prepend <token> or not, depending on the users role/groups type 
    my ($name,$school_token,$role) = @_;
    my $name_tokened="";
    if ($role eq "adminclass" or
        $role eq "room" or 
        $role eq "roomws" or
        $role eq "examaccount" or
        $role eq "workstation"){
        if ($school_token eq "---" or $school_token eq ""){
            # no multischool
            $name_tokened=$name;
        } else {
            # multischool
            $name_tokened=$school_token."-".$name;
        }
        return $name_tokened;
    } elsif ($role eq "teacher" or
             $role eq "student"){
        return $name;
    } elsif ($role eq "project"){
        # project: no token-prefix
        unless ($name =~ m/^p\_/) { 
            # add refix to projects: p_ 
            $name="p_".$name;
        }
        return $name;
    } else {
        return $name;
    }
}



sub AD_get_container {
    # returns empty string or container followed by comma
    # i.e. >< OR >CN=Students,< 
    # first option: role(user) OR type(group)
    # second option: groupname (with token, i.e. pks-7a) 
    my ($role,$group) = @_;
    my $group_strg="OU=".$group.",";
    my $container="";
    # for user container
    if ($role eq "student"){
        $container=$group_strg.$DevelConf::AD_student_ou;
    }  elsif ($role eq "teacher"){
        $container=$group_strg.$DevelConf::AD_teacher_ou;
    }  elsif ($role eq "workstation"){
        $container=$group_strg.$DevelConf::AD_workstation_ou;
    }  elsif ($role eq "examaccount"){
        $container=$group_strg.$DevelConf::AD_examaccount_ou;
    # group container
    }  elsif ($role eq "adminclass"){
        $container=$DevelConf::AD_class_ou;
    }  elsif ($role eq "project"){
        $container=$DevelConf::AD_project_ou;
    }  elsif ($role eq "room"){
        $container=$DevelConf::AD_room_ou;
    # other
    }  elsif ($role eq "management"){
        $container=$DevelConf::AD_management_ou;
    }  elsif ($role eq "printer"){
        $container=$DevelConf::AD_printer_ou;
    }
    # add the comma if necessary
    if ($container ne ""){
        $container=$container.",";
    }
}


sub AD_ou_add {
    # if $result->code is not given, the add is silent
    my ($ldap,$root_dse,$ou,$token) = @_;
    $ou=&AD_get_ou_tokened($ou);
    if ($token eq "---"){
        $token=""; # OU=SCHOOL
    } else {
        $token=$token."-";
    }
    if($Conf::log_level>=2){
        print "Adding OU=$ou ($token) ...\n";
    }

    my $dn="OU=".$ou.",".$root_dse;
    # provide that a ou SCHOOLNAME exists
    my $result = $ldap->add($dn,attr => ['objectclass' => ['top', 'organizationalUnit']]);

    if($Conf::log_level>=2){
        print "   * Adding sub ou's ...\n";
    }
    # ous for users
    my $student=$DevelConf::AD_student_ou.",".$dn;
    $result = $ldap->add($student,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    my $teacher=$DevelConf::AD_teacher_ou.",".$dn;
    $result = $ldap->add($teacher,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    my $workstation=$DevelConf::AD_workstation_ou.",".$dn;
    $result = $ldap->add($workstation,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    my $examaccount=$DevelConf::AD_examaccount_ou.",".$dn;
    $result = $ldap->add($examaccount,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    # group ou
    my $class=$DevelConf::AD_class_ou.",".$dn;
    $result = $ldap->add($class,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    my $room=$DevelConf::AD_room_ou.",".$dn;
    $result = $ldap->add($room,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    # other
    my $management=$DevelConf::AD_management_ou.",".$dn;
    $result = $ldap->add($management,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    my $printer=$DevelConf::AD_printer_ou.",".$dn;
    $result = $ldap->add($printer,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    my $custom=$DevelConf::AD_custom_ou.",".$dn;
    $result = $ldap->add($custom,attr => ['objectclass' => ['top', 'organizationalUnit']]);

    # Adding some groups
    # <token>teachers
    my $group=$token.$DevelConf::teacher;
    my $dn_group="CN=".$group.",".$DevelConf::AD_class_ou.",".$dn;
    if($Conf::log_level>=2){
        print "   * Adding group $group\n";
    }
    $result = $ldap->add( $dn_group,
                         attr => [
                             'cn'   => $group,
                             'sAMAccountName' => $group,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );

    # <token>students
    $group=$token.$DevelConf::student;
    $dn_group="CN=".$group.",".$DevelConf::AD_class_ou.",".$dn;
    if($Conf::log_level>=2){
        print "   * Adding group $group\n";
    }
    $result = $ldap->add( $dn_group,
                         attr => [
                             'cn'   => $group,
                             'sAMAccountName' => $group,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );

    # <token>examaccounts
    $group=$token.$DevelConf::examaccount;
    $dn_group="CN=".$group.",".$DevelConf::AD_room_ou.",".$dn;
    if($Conf::log_level>=2){
        print "   * Adding group $group\n";
    }
    $result = $ldap->add( $dn_group,
                         attr => [
                             'cn'   => $group,
                             'sAMAccountName' => $group,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );

    ## <token>workstations
    ## workstations sind in keiner Gruppe
    #$group=$token.$DevelConf::workstation;
    #$dn_group="CN=".$group.",".$DevelConf::AD_room_ou.",".$dn;
    #if($Conf::log_level>=2){
    #    print "   * Adding group $group\n";
    #} 
    #$result = $ldap->add( $dn_group,
    #                     attr => [
    #                         'cn'   => $group,
    #                         'sAMAccountName' => $group,
    #                         'objectclass' => ['top',
    #                                           'group' ],
    #                     ]
    #                 );


    ############################################################
    # OU=SOPHOMORIX
    my $sophomorix_dn=$DevelConf::AD_sophomorix_ou.",".$root_dse;
    if($Conf::log_level>=2){
        print "Adding $sophomorix_dn\n";
    }
    $result = $ldap->add($sophomorix_dn,attr => ['objectclass' => ['top', 'organizationalUnit']]);

    if($Conf::log_level>=2){
        print "   * Adding sub ou's ...\n";
    }
    # Multigroups ou
    my $multigroup=$DevelConf::AD_multigroup_ou.",".$sophomorix_dn;
    $result = $ldap->add($multigroup,attr => ['objectclass' => ['top', 'organizationalUnit']]);

    # Projects ou
    my $projects=$DevelConf::AD_project_ou.",".$sophomorix_dn;
    $result = $ldap->add($projects,attr => ['objectclass' => ['top', 'organizationalUnit']]);

    # students in Multigroups,OU=SOPHOMORIX
    my $sophomorix_dn_group="CN=multi-".$DevelConf::student.",".$DevelConf::AD_multigroup_ou.",".$sophomorix_dn;
    $result = $ldap->add( $sophomorix_dn_group,
                         attr => [
                             'cn'   => "multi-".$DevelConf::student,
                             'sAMAccountName' => "multi-".$DevelConf::student,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );
    if($Conf::log_level>=2){
        print "   * Adding OU=SOPHOMOROX multi-groups ...\n";
    }
    # teachers in Multigroups,OU=SOPHOMORIX
    $sophomorix_dn_group="CN=multi-".$DevelConf::teacher.",".$DevelConf::AD_multigroup_ou.",".$sophomorix_dn;
    $result = $ldap->add( $sophomorix_dn_group,
                         attr => [
                             'cn'   => "multi-".$DevelConf::teacher,
                             'sAMAccountName' => "multi-".$DevelConf::teacher,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );
    # workstations in Multigroups,OU=SOPHOMORIX
    $sophomorix_dn_group="CN=multi-".$DevelConf::workstation.",".$DevelConf::AD_multigroup_ou.",".$sophomorix_dn;
    $result = $ldap->add( $sophomorix_dn_group,
                         attr => [
                             'cn'   => "multi-".$DevelConf::workstation,
                             'sAMAccountName' => "multi-".$DevelConf::workstation,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );
    # ExamAccounts in Multigroups,OU=SOPHOMORIX
    $sophomorix_dn_group="CN=multi-".$DevelConf::examaccount.",".$DevelConf::AD_multigroup_ou.",".$sophomorix_dn;
    $result = $ldap->add( $sophomorix_dn_group,
                         attr => [
                             'cn'   => "multi-".$DevelConf::examaccount,
                             'sAMAccountName' => "multi-".$DevelConf::examaccount,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );
    &AD_debug_logdump($result,2,(caller(0))[3]);
}



sub AD_object_search {
    my ($ldap,$root_dse,$type,$name) = @_;
    # returns 0,"" or 1,"dn of object"
    # type: group, user, ...
    # check if object exists
    # (&(objectclass=user)(cn=pete)
    # (&(objectclass=group)(cn=7a)
    my $filter="(&(objectclass=".$type.") (cn=".$name."))"; 
    my $mesg = $ldap->search(
                      base   => $root_dse,
                      scope => 'sub',
                      filter => $filter,
                      attr => ['cn']
                            );
    &AD_debug_logdump($mesg,2,(caller(0))[3]);
    my $count = $mesg->count;
    if ($count > 0){
        # process first entry
        my ($entry,@entries) = $mesg->entries;
        my $dn = $entry->dn();
        my $cn = $entry->get_value ('cn');
        $cn="CN=".$cn;
        return ($count,$dn,$cn);
    } else {
        return (0,"","");
    }
}

sub AD_workstation_fetch {
    my %domcomputers_system = ();
    my %rooms_system = ();
    my %examaccounts_system = ();

    print "\nWARNING: not fetching workstation data from AD\n\n";

    return(\%domcomputers_system, 
           \%rooms_system, 
           \%examaccounts_system, 
          );
}



sub AD_object_move {
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
    my $dn = $arg_ref->{dn};
    my $target_branch = $arg_ref->{target_branch};
    my $rdn = $arg_ref->{rdn};

    &Sophomorix::SophomorixBase::print_title("Move object in tree:");
    print "   * DN:     $dn\n";
    print "   * Target: $target_branch\n";

    # create branch
    my $result = $ldap->add($target_branch,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    &AD_debug_logdump($result,2,(caller(0))[3]);
    # move object
    $result = $ldap->moddn ( $dn,
                        newrdn => $rdn,
                        deleteoldrdn => '1',
                        newsuperior => $target_branch
                               );
    &AD_debug_logdump($result,2,(caller(0))[3]);
}



sub AD_group_create {
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
    my $root_dse = $arg_ref->{root_dse};
    my $group = $arg_ref->{group};
    my $ou = $arg_ref->{ou};
    my $type = $arg_ref->{type};
    my $school_token = $arg_ref->{school_token};

    $ou=&AD_get_ou_tokened($ou);

    # calculate missing Attributes
    my $container=&AD_get_container($type,$group);
    my $dn = "CN=".$group.",".$container."OU=".$ou.",".$root_dse;

    my ($count,$dn_exist,$cn_exist)=&AD_object_search($ldap,$root_dse,"group",$group);
    if ($count==0){
        # adding the group
        &Sophomorix::SophomorixBase::print_title("Creating Group (begin):");
        print("   DN:       $dn\n");
        print("   Group:    $group\n");
        print("   Type:     $type\n");
        my $result = $ldap->add( $dn,
                                attr => [
                                    'cn'   => $group,
                                    'sAMAccountName' => $group,
                                    'objectclass' => ['top',
                                                      'group' ],
                                ]
                            );
        $result->code && warn "failed to add entry: ", $result->error ;
        &AD_debug_logdump($result,2,(caller(0))[3]);
    } else {
        print "   * Group $group exists already ($count results)\n";
        #return;
    }
    if ($type eq "adminclass"){
        my $teacher_group_expected=&AD_get_name_tokened($DevelConf::teacher,$school_token,"adminclass");
        if ($group eq $teacher_group_expected){
            # add <token>-teachers to multi-teachers
            &AD_group_addmember({ldap => $ldap,
                                 root_dse => $root_dse, 
                                 group => "multi-".$DevelConf::teacher,
                                 addgroup => $group,
                               });
        } else {
            # a group like 7a, 7b
            #print "Student class of the school: $group\n";
            my $token_students=&AD_get_name_tokened($DevelConf::student,$school_token,"adminclass");
            # add the group to <token>-students
            &AD_group_addmember({ldap => $ldap,
                                 root_dse => $root_dse, 
                                 group => $token_students,
                                 addgroup => $group,
                               });
            # add group <token>-students to multi-students
            &AD_group_addmember({ldap => $ldap,
                                 root_dse => $root_dse, 
                                 group => "multi-".$DevelConf::student,
                                 addgroup => $token_students,
                               });
        }
    } elsif ($type eq "room"){
        my $token_examaccounts=$school_token."-".$DevelConf::examaccount;
        # add the room to <token>-examaccounts
        &AD_group_addmember({ldap => $ldap,
                             root_dse => $root_dse, 
                             group => $token_examaccounts,
                             addgroup => $group,
                           });
        # add group <token>-examaccounts to multi-examaccounts
        &AD_group_addmember({ldap => $ldap,
                             root_dse => $root_dse, 
                             group => "multi-".$DevelConf::examaccount,
                             addgroup => $token_examaccounts,
                           });
    }
    &Sophomorix::SophomorixBase::print_title("Creating Group (end)");
    return;
}



sub AD_group_addmember {
    # requires token-group as groupname
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
    my $root_dse = $arg_ref->{root_dse};
    my $group = $arg_ref->{group};
    my $adduser = $arg_ref->{addmember};
    my $addgroup = $arg_ref->{addgroup};
    my ($count_group,$dn_exist_group,$cn_exist_group)=&AD_object_search($ldap,$root_dse,"group",$group);

    &Sophomorix::SophomorixBase::print_title("Adding member to $group:");
    if ($count_group==0){
        # group does not exist -> exit with warning
        print "   * WARNING: Group $group nonexisting ($count_group results)\n";
        return;
     }

     if (defined $adduser){
         my ($count,$dn_exist,$cn_exist)=&AD_object_search($ldap,$root_dse,"user",$adduser);
         print "   * Adding user $adduser to group $group\n";
         if ($count > 0){
             print "   * User $adduser exists ($count results)\n";
             my $mesg = $ldap->modify( $dn_exist_group,
     	        	              add => {
                                    member => $dn_exist,
                               }
                           );
             &AD_debug_logdump($mesg,2,(caller(0))[3]);
             #my $command="samba-tool group addmembers ". $group." ".$adduser;
             #print "   # $command\n";
             #system($command);
             return;
         }
     } elsif (defined $addgroup){
         print "   * Adding group $addgroup to $group\n";
         my ($count_group,$dn_exist_addgroup,$cn_exist_addgroup)=&AD_object_search($ldap,$root_dse,"group",$addgroup);
         if ($count_group > 0){
             print "   * Group $addgroup exists ($count_group results)\n";
             my $mesg = $ldap->modify( $dn_exist_group,
     	    	                   add => {
                                       member => $dn_exist_addgroup,
                                   }
                               );
             &AD_debug_logdump($mesg,2,(caller(0))[3]);
             return;
         }
     } else {
         return;
     }
}



sub AD_group_removemember {
    # requires token-group as groupname
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
    my $root_dse = $arg_ref->{root_dse};
    my $group = $arg_ref->{group};
    my $removeuser = $arg_ref->{removemember};
    my $removegroup = $arg_ref->{removegroup};
    &Sophomorix::SophomorixBase::print_title("Removing member from $group:");

    my ($count_group,$dn_exist_group,$cn_exist_group)=&AD_object_search($ldap,$root_dse,"group",$group);
    if ($count_group==0){
        # group does not exist -> create group
        print "   * WARNING: Group $group nonexisting ($count_group results)\n";
        return;
    }

    if (defined $removeuser){
        my ($count,$dn_exist,$cn_exist)=&AD_object_search($ldap,$root_dse,"user",$removeuser);
        print "   * Removing user $removeuser from group $group\n";
        if ($count > 0){
            print "   * User $removeuser exists ($count results)\n";
            my $mesg = $ldap->modify( $dn_exist_group,
	  	                  delete => {
                                      member => $dn_exist,
                                  }
                              );
            #my $command="samba-tool group removemembers ". $group." ".$removeuser;
            #print "   # $command\n";
            #system($command);
            return;
        }
    } elsif (defined $removegroup){
         print "   * Removing group $removegroup from $group\n";
         my ($count_group,$dn_exist_removegroup,$cn_exist_removegroup)=&AD_object_search($ldap,$root_dse,"group",$removegroup);
         if ($count_group > 0){
             print "   * Group $removegroup exists ($count_group results)\n";
             my $mesg = $ldap->modify( $dn_exist_group,
     	    	                   delete => {
                                       member => $dn_exist_removegroup,
                                   }
                               );
             &AD_debug_logdump($mesg,2,(caller(0))[3]);
             return;
         }
    } else {
        return;
    }
}



sub  get_forbidden_logins{
    my ($ldap,$root_dse) = @_;
    my %forbidden_logins = %DevelConf::forbidden_logins;

    # users from ldap
    $mesg = $ldap->search( # perform a search
                   base   => $root_dse,
                   scope => 'sub',
                   filter => '(objectClass=user)',
                   attr => ['sAMAccountName']
                         );
    my $max_user = $mesg->count; 
    for( my $index = 0 ; $index < $max_user ; $index++) {
        my $entry = $mesg->entry($index);
        my @values = $entry->get_value( 'sAMAccountName' );
        foreach my $login (@values){
            $forbidden_logins{$login}="login in AD";
        }
    }

    # users in /etc/passwd
    if (-e "/etc/passwd"){
        open(PASS, "/etc/passwd");
        while(<PASS>) {
            my ($login)=split(/:/);
            $forbidden_logins{$login}="login in /etc/passwd";
        }
        close(PASS);
    }

    # future groups in schueler.txt
    my $schueler_file=$DevelConf::path_conf_user."/schueler.txt";
    if (-e "$schueler_file"){
        open(STUDENTS, "$schueler_file");
        while(<STUDENTS>) {
            my ($group)=split(/;/);
            chomp($group);
            if ($group ne ""){
                $forbidden_logins{$group}="future group in schueler.txt";
   	    }
         }
         close(STUDENTS);
    }

    # groups from ldap
    $mesg = $ldap->search( # perform a search
                   base   => $root_dse,
                   scope => 'sub',
                   filter => '(objectClass=group)',
                   attr => ['sAMAccountName']
                         );
    my $max_group = $mesg->count; 
    for( my $index = 0 ; $index < $max_group ; $index++) {
        my $entry = $mesg->entry($index);
        my @values = $entry->get_value( 'sAMAccountName' );
        foreach my $group (@values){
            $forbidden_logins{$group}="group in AD";
        }
    }

    # groups in /etc/group
    if (-e "/etc/group"){
        open(GROUP, "/etc/group");
        while(<GROUP>) {
            my ($group)=split(/:/);
            $forbidden_logins{$group}="group in /etc/group";
        }
        close(GROUP);
    }

    # output forbidden logins:
    if($Conf::log_level>=3){
        print("Login-Name:                    ",
              "                                   Status:\n");
        print("================================",
              "===========================================\n");
        while (($k,$v) = each %forbidden_logins){
            printf "%-50s %3s\n","$k","$v";
        }
    }
    return %forbidden_logins;
}



sub AD_debug_logdump {
    # dumping ldap message object in loglevels
    my ($message,$level,$text) = @_;
    if($Conf::log_level>=$level){
        if ( $message->code) { # 0: no error
            print "   Debug info from server($text):\n";
            print Dumper(\$message);
        }
    }
}





# END OF FILE
# Return true=1
1;
