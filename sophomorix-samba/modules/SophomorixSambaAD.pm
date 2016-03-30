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
            AD_user_move
            AD_user_kill
            AD_group_create
            AD_group_addmember
            AD_group_removemember
            AD_get_group_by_token
            get_forbidden_logins
            AD_ou_add
            AD_get_base
            AD_object_search
            AD_object_move
            );

sub AD_get_passwd {
    my $smb_pwd="";
    my $smb_rootdn=&AD_get_base();
    #my $smb_rootdn="DC=linuxmuster,DC=local";
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
    return($smb_pwd,$smb_rootdn);
}


sub AD_bind_admin {
    my ($smb_pwd,$smb_rootdn)=&AD_get_passwd();
    my $admin_dn="CN=Administrator,CN=Users,".$smb_rootdn;
    # check connection to Samba4 AD
    if($Conf::log_level>=3){
        print "   Checking Samba4 AD connection ...\n";
    }
    #my $ldap = Net::LDAP->new('ldaps://localhost')  or  die "$@";
    my $ldap = Net::LDAP->new('ldaps://localhost')  or  
         &Sophomorix::SophomorixBase::log_script_exit(
                            "No connection to Samba4 AD!",
         1,1,0,@arguments);
    my $mesg = $ldap->bind($admin_dn, password => $smb_pwd);
    # show errors from bind
    $mesg->code && die $mesg->error;
    return $ldap;
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
    my $user = $arg_ref->{login};
    my $identifier = $arg_ref->{identifier};

    my ($count,$dn_exist,$cn_exist)=&AD_object_search($ldap,"user",$user);
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



sub AD_user_create {
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
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
    my $creationdate = $arg_ref->{creationdate};

    #calculate
    my $shell="/bin/false";
    my $display_name = $firstname_utf8." ".$surname_utf8;
    my $user_principal_name = $login."\@"."linuxmuster.local";
    # dn
    my $base=&AD_get_base();
    my $group_token=&AD_get_group_by_token($group,$school_token,$role);
    my $container=&AD_get_container($role,$group_token);

    my $dn_class = $container."OU=".$ou.",".$base;
    my $dn = "cn=".$login.",".$container."OU=".$ou.",".$base;
 
    # password generation
    # build the conversion map from your local character set to Unicode    
    my $charmap = Unicode::Map8->new('latin1')  or  die;
    # surround the PW with double quotes and convert it to UTF-16
    my $uni_password = $charmap->tou('"'.$plain_password.'"')->byteswap()->utf16();

    if($Conf::log_level>=1){
        print "\n";
        &Sophomorix::SophomorixBase::print_title("Creating User $user_count :");
        print("DN:                 $dn\n");
        print("DN (Parent):        $dn_class\n");
        print("Surname (ASCII):    $surname_ascii\n");
        print("Surname (UTF8):     $surname_utf8\n");
        print("Firstname (ASCII):  $firstname_ascii\n");
        print("Firstname (UTF8):   $firstname_utf8\n");
        print("Birthday:           $birthdate\n");
        print("Identifier:         $identifier\n");
        print("OU:                 $ou\n"); # Organisatinal Unit
        print("School Token:       $school_token\n"); # Organisatinal Unit
        print("Role:               $role\n");
        print("AdminClass:         $group ($group_token)\n"); # lehrer oder klasse
        print("Unix-gid:           $wunsch_gid\n"); # lehrer oder klasse
        #print("GECOS:              $gecos\n");
        #print("Login (to check):   $login_name_to_check\n");
        print("Login (check OK):   $login\n");
        print("Password:           $plain_password\n");
        # sophomorix stuff


        print("Creationdate:       $creationdate\n");

        print("Unid:               $unid\n");
        print("Unix-id:            $wunsch_id\n");
    }

    $ldap->add($dn_class,attr => ['objectclass' => ['top', 'container']]);
    my $result = $ldap->add( $dn,
                   attr => [
                   'sAMAccountName' => $login,
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
                           ]
                           );
    $result->code && warn "failed to add entry: ", $result->error ;
}



sub AD_user_move {
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
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
    my $base=&AD_get_base();
    my $group_type_old;
    my $group_type_new;
    my $target_branch;
    if ($role_new eq "student"){
        $group_type_old = $school_token_old."-".$DevelConf::student;
        $group_type_new = $school_token_new."-".$DevelConf::student;
        $target_branch="CN=".$group_new.",CN=Students,OU=".$ou_new.",".$base;
    } elsif ($role_new eq "teacher"){
        $group_type_old = $school_token_old."-".$DevelConf::teacher;
        $group_type_new = $school_token_new."-".$DevelConf::teacher;
        $target_branch="CN=".$group_new.",CN=Teachers,OU=".$ou_new.",".$base;
    }

    # fetch the dn (where the object really is)
    my ($count,$dn,$rdn)=&AD_object_search($ldap,"user",$user);
    if ($count==0){
        print "\nWARNING: $user not found in ldap, skipping\n\n";
        next;
    }
    my ($count_group_old,
        $dn_group_old,
        $rdn_group_old)=&AD_object_search($ldap,"group",$group_old);
    if ($count_group_old==0){
        print "\nWARNING: Group $group_old not found in ldap, skipping\n\n";
        next;
    }
    if($Conf::log_level>=1){
        print "\n";
        &Sophomorix::SophomorixBase::print_title("Moving User $user ($user_count):");

        print("DN:                $dn\n");
        print("Target DN:         $target_branch\n");
        print("Group (Old):       $group_old\n");
        print("Group (New):       $group_new\n");
        print("Role (New):        $role_new\n");
        print("Group (Old):       $group_type_old\n");
        print("Group (New):       $group_type_new\n");
        print("School(Old):       $school_token_old ($ou_old)\n");
        print("School(New):       $school_token_new ($ou_new)\n");
    }

    # make sure OU and tree exists
#    if (not exists $ou_created{$ou_new}){
#         # create new ou
         &AD_ou_add($ldap,$ou_new,$school_token_new);
#         # remember new ou to add it only once
#         $ou_created{$ou_new}="already created";
#     }

    # make sure new group exits
    &AD_group_create({ldap=>$ldap,
                     group=>$group_new,
                     ou=>$ou_new,
                     school_token=>$school_token_new,
                     type=>"adminclass",
                    });

    # why test group that has been added just now ?????   
    #my ($count_group_new,
    #    $dn_group_new,
    #    $rdn_group_new)=&AD_object_search($ldap,"group",$group_new);
    #if ($count_group_new==0){
    #    print "\nWARNING: Group $group_new not found in ldap, skipping\n\n";
    #    next;
    #}
    my $mesg = $ldap->modify( $dn,
		      replace => {
                          sophomorixAdminClass => $group_new,
                          sophomorixExitAdminClass => $group_old,
                          sophomorixSchoolPrefix => $school_token_new,
                          sophomorixSchoolname => $ou_new,
                          sophomorixRole => $role_new,
                      }
               );
    #print Dumper(\$mesg);

#    $mesg = $ldap->modify( $dn_group_old,
#		      delete => {
#                          member => $dn,
#                      }
#               );
#
#    $mesg = $ldap->modify( $dn_group_new,
#		      add => {
#                          member => $dn,
#                      }
#               );

    # change group
    &AD_group_removemember({ldap => $ldap, 
                            group => $group_old,
                            removemember => $user,
                          });   

    &AD_group_addmember({ldap => $ldap,
                         group => $group_new,
                         addmember => $user,
                       }); 

    # change rolegroup
    #if ($group_type_old ne $group_type_new){
    #    &AD_group_removemember({ldap => $ldap, 
    #                            group => $group_type_old,
    #                            removemember => $user,
    #                          });   
    #    &AD_group_addmember({ldap => $ldap,
    #                         group => $group_type_new,
    #                         addmember => $user,
    #                      }); 
    #}
  
    &AD_object_move({ldap=>$ldap,
                     dn=>$dn,
                     rdn=>$rdn,
                     target_branch=>$target_branch,
                    });
}


sub AD_get_base {
    # ?????
    return "DC=linuxmuster,DC=local";
}



sub AD_get_group_by_token {
    my ($group,$school_token,$role) = @_;
    my $groupname="";
    if ($role eq "adminclass" or $role eq "student" or $role eq "teacher"){
        if ($school_token eq "---" or $school_token eq ""){
            # no multischool
            $groupname=$group;
        } else {
            # multischool
            $groupname=$school_token."-".$group;
        }
        return $groupname;
    } elsif ($role eq "project"){
        # project: no token-prefix
        return $group;
    } else {
        return $group;
    }
}



sub AD_get_container {
    # returns empty string or container followed by comma
    # i.e. >< OR >CN=Students,< 
    # first option: role(user) OR type(group)
    # second option: groupname (with token, i.e. pks-7a) 
    my ($role,$group) = @_;
    my $group_strg="CN=".$group.",";
    my $container="";
    if ($role eq "student"){
        $container=$group_strg.$DevelConf::AD_student_cn;
    }  elsif ($role eq "teacher"){
        $container=$group_strg.$DevelConf::AD_teacher_cn;
    }  elsif ($role eq "adminclass"){
        $container=$DevelConf::AD_class_cn;
    }  elsif ($role eq "project"){
        $container=$DevelConf::AD_project_cn;
    }  elsif ($role eq "workstation"){
        $container=$group_strg.$DevelConf::AD_workstation_cn;
    }  elsif ($role eq "examaccount"){
        $container=$group_strg.$DevelConf::AD_examaccount_cn;
    }  elsif ($role eq "management"){
        $container=$DevelConf::AD_management_cn;
    }  elsif ($role eq "printer"){
        $container=$DevelConf::AD_printer_cn;
    }
    # add the comma if necessary
    if ($container ne ""){
        $container=$container.",";
    }
}


sub AD_ou_add {
    # if $result->code is not given, the add is silent
    my ($ldap,$ou,$token) = @_;
    my $base=&AD_get_base();
    my $dn="OU=".$ou.",".$base;
    # provide that a ou exists
    my $result = $ldap->add($dn,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    #$result->code && warn "failed to add entry: ", $result->error ;
    my $student=$DevelConf::AD_student_cn.",".$dn;
    $result = $ldap->add($student,attr => ['objectclass' => ['top', 'container']]);
    my $teacher=$DevelConf::AD_teacher_cn.",".$dn;
    $result = $ldap->add($teacher,attr => ['objectclass' => ['top', 'container']]);
    my $class=$DevelConf::AD_class_cn.",".$dn;
    $result = $ldap->add($class,attr => ['objectclass' => ['top', 'container']]);
    my $project=$DevelConf::AD_project_cn.",".$dn;
    $result = $ldap->add($project,attr => ['objectclass' => ['top', 'container']]);
    my $workstation=$DevelConf::AD_workstation_cn.",".$dn;
    $result = $ldap->add($workstation,attr => ['objectclass' => ['top', 'container']]);
    my $examaccount=$DevelConf::AD_examaccount_cn.",".$dn;
    $result = $ldap->add($examaccount,attr => ['objectclass' => ['top', 'container']]);
    my $management=$DevelConf::AD_management_cn.",".$dn;
    $result = $ldap->add($management,attr => ['objectclass' => ['top', 'container']]);
    my $printer=$DevelConf::AD_printer_cn.",".$dn;
    $result = $ldap->add($printer,attr => ['objectclass' => ['top', 'container']]);
    my $custom=$DevelConf::AD_custom_cn.",".$dn;
    $result = $ldap->add($custom,attr => ['objectclass' => ['top', 'container']]);
    # Adding some groups

    # token-teachers
    my $group=$token."-".$DevelConf::teacher;
    my $dn_group="CN=".$group.",".$DevelConf::AD_class_cn.",".$dn;
    $result = $ldap->add( $dn_group,
                         attr => [
                             'cn'   => $group,
                             'sAMAccountName' => $group,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );

    # token-students
    $group=$token."-".$DevelConf::student;
    $dn_group="CN=".$group.",".$DevelConf::AD_class_cn.",".$dn;
    $result = $ldap->add( $dn_group,
                         attr => [
                             'cn'   => $group,
                             'sAMAccountName' => $group,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );

    # OU=SOPHOMORIX
    my $sophomorix_dn="OU=SOPHOMORIX,".$base;
    $result = $ldap->add($sophomorix_dn,attr => ['objectclass' => ['top', 'organizationalUnit']]);
    $class=$DevelConf::AD_class_cn.",".$sophomorix_dn;
    $result = $ldap->add($class,attr => ['objectclass' => ['top', 'container']]);
    # students in OU=SOPHMORIX
    my $sophomorix_dn_group="CN=".$DevelConf::student.",".$DevelConf::AD_class_cn.",".$sophomorix_dn;
    $result = $ldap->add( $sophomorix_dn_group,
                         attr => [
                             'cn'   => $DevelConf::student,
                             'sAMAccountName' => $DevelConf::student,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );

    # teachers in OU=SOPHMORIX
    $sophomorix_dn_group="CN=".$DevelConf::teacher.",".$DevelConf::AD_class_cn.",".$sophomorix_dn;
    $result = $ldap->add( $sophomorix_dn_group,
                         attr => [
                             'cn'   => $DevelConf::teacher,
                             'sAMAccountName' => $DevelConf::teacher,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );
    # workstations in OU=SOPHMORIX
    $sophomorix_dn_group="CN=".$DevelConf::workstation.",".$DevelConf::AD_class_cn.",".$sophomorix_dn;
    $result = $ldap->add( $sophomorix_dn_group,
                         attr => [
                             'cn'   => $DevelConf::workstation,
                             'sAMAccountName' => $DevelConf::workstation,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );
    # ExamAccounts in OU=SOPHMORIX
    $sophomorix_dn_group="CN=".$DevelConf::exam_accounts.",".$DevelConf::AD_class_cn.",".$sophomorix_dn;
    $result = $ldap->add( $sophomorix_dn_group,
                         attr => [
                             'cn'   => $DevelConf::exam_accounts,
                             'sAMAccountName' => $DevelConf::exam_accounts,
                             'objectclass' => ['top',
                                               'group' ],
                         ]
                     );
    #print Dumper(\$result);
}



sub AD_object_search {
    my ($ldap,$type,$name) = @_;
    # returns 0,"" or 1,"dn of object"
    # type: group, user, ...
    # check if object exists
    # (&(objectclass=user)(cn=pete)
    # (&(objectclass=group)(cn=7a)
    my $filter="(&(objectclass=".$type.") (cn=".$name."))"; 
    my $base=&AD_get_base();
    my $mesg = $ldap->search(
                      base   => $base,
                      scope => 'sub',
                      filter => $filter,
                      attr => ['cn']
                            );
    #print Dumper(\$mesg);
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



sub AD_object_move {
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
    my $dn = $arg_ref->{dn};
    my $target_branch = $arg_ref->{target_branch};
    my $rdn = $arg_ref->{rdn};

    # create branch
    my $result = $ldap->add($target_branch,attr => ['objectclass' => ['top', 'container']]);
    #print Dumper(\$result);

    # move object
    $result = $ldap->moddn ( $dn,
                        newrdn => $rdn,
                        deleteoldrdn => '1',
                        newsuperior => $target_branch
                               );
    print Dumper(\$result);
}



sub AD_group_create {
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
    my $group = $arg_ref->{group};
    my $ou = $arg_ref->{ou};
    my $type = $arg_ref->{type};
    my $school_token = $arg_ref->{school_token};

    #my $group_token=&AD_get_group_by_token($group,$school_token,$type);

    # calculate missing Attributes
    my $base=&AD_get_base();
    my $container=&AD_get_container($type,$group);
    my $dn = "cn=".$group.",".$container."OU=".$ou.",".$base;

    my ($count,$dn_exist,$cn_exist)=&AD_object_search($ldap,"group",$group);
    if ($count> 0){
        print "   * Group $group exists already ($count results)\n";
        return;
    }

    # adding the group
    &Sophomorix::SophomorixBase::print_title("Creating Group:");
    print("   Group:    $group\n");
    print("   Type:     $type\n");
    print("   dn:       $dn\n");
    my $result = $ldap->add( $dn,
                           attr => [
                             'cn'   => $group,
                             'sAMAccountName' => $group,
                             'objectclass' => ['top',
                                               'group' ],
                                   ]
                           );
    $result->code && warn "failed to add entry: ", $result->error ;

    if ($type eq "adminclass"){
        # make the group a member of <token>-students
        my $token_students=$school_token."-".$DevelConf::student;
        &AD_group_addmember({ldap => $ldap,
                             group => $token_students,
                             addgroup => $group,
                           });
        if ($group eq "teachers"){
            my $token_teachers=$school_token."-".$DevelConf::teachers;
            &AD_group_addmember({ldap => $ldap,
                                 group => $DevelConf::teachers,
                                 addgroup => $token_teachers,
                               });
        } else {
            my $token_students=$school_token."-".$DevelConf::student;
            &AD_group_addmember({ldap => $ldap,
                                 group => $DevelConf::student,
                                 addgroup => $token_students,
                               });
        }
    }
    return;
}



sub AD_group_addmember {
    # requires token-group as groupname
    my ($arg_ref) = @_;
    my $ldap = $arg_ref->{ldap};
    my $group = $arg_ref->{group};
    my $adduser = $arg_ref->{addmember};
    my $addgroup = $arg_ref->{addgroup};

    my ($count_group,$dn_exist_group,$cn_exist_group)=&AD_object_search($ldap,"group",$group);
    if ($count_group==0){
        # group does not exist -> exit with warning
        print "   * WARNING: Group $group nonexisting ($count_group results)\n";
        return;
     }

     if (defined $adduser){
         my ($count,$dn_exist,$cn_exist)=&AD_object_search($ldap,"user",$adduser);
         if ($count > 0){
             print "   * User $adduser exists ($count results)\n";
             print "Adding user $adduser to group $group\n";
             my $mesg = $ldap->modify( $dn_exist_group,
     	        	              add => {
                                    member => $dn_exist,
                               }
                           );
             #print Dumper(\$mesg);

             #my $command="samba-tool group addmembers ". $group." ".$adduser;
             #print "   # $command\n";
             #system($command);
             return;
         }
     } elsif (defined $addgroup){
         print "Adding Group $addgroup to $group\n";
         my ($count_group,$dn_exist_addgroup,$cn_exist_addgroup)=&AD_object_search($ldap,"group",$addgroup);
         if ($count_group > 0){
             print "   * Group $addgroup exists ($count_group results)\n";
             print "Adding group $addgroup to group $group\n";
             my $mesg = $ldap->modify( $dn_exist_group,
     	    	                   add => {
                                       member => $dn_exist_addgroup,
                                   }
                               );
             #print Dumper(\$mesg);
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
    my $group = $arg_ref->{group};
    my $removeuser = $arg_ref->{removemember};
    my $removegroup = $arg_ref->{removegroup};

    my ($count_group,$dn_exist_group,$cn_exist_group)=&AD_object_search($ldap,"group",$group);
    if ($count_group==0){
        # group does not exist -> create group
        print "   * WARNING: Group $group nonexisting ($count_group results)\n";
        return;
    }

    if (defined $removeuser){
        my ($count,$dn_exist,$cn_exist)=&AD_object_search($ldap,"user",$removeuser);
        if ($count > 0){
            print "   * User $removeuser exists ($count results)\n";
            print "Removing $removeuser from group $group\n";

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
         print "Removing Group $removegroup from $group\n";
         my ($count_group,$dn_exist_removegroup,$cn_exist_removegroup)=&AD_object_search($ldap,"group",$removegroup);
         if ($count_group > 0){
             print "   * Group $removegroup exists ($count_group results)\n";
             print "Removing group $removegroup from group $group\n";
             my $mesg = $ldap->modify( $dn_exist_group,
     	    	                   delete => {
                                       member => $dn_exist_removegroup,
                                   }
                               );
             #print Dumper(\$mesg);
             return;
         }
    } else {
        return;
    }
}



sub  get_forbidden_logins{
    my ($ldap) = @_;
    my %forbidden_logins = %DevelConf::forbidden_logins;

    my $base=&AD_get_base();
 
    # users from ldap
    $mesg = $ldap->search( # perform a search
                   base   => $base,
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
                   base   => $base,
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







# END OF FILE
# Return true=1
1;
