#!/usr/bin/perl
#
use strict;
use warnings;

use Data::Dumper;

my $codeblock; 

my $File = $ARGV[0];
my $Target = $ARGV[1];
my $CPP = $ARGV[2];

sub line_process {
   my ($fh) = @_;

   my %Chunks;

   my $chunkstart;
   my $inchunk = undef;
   my $in_ifdef = undef;
   my $i = 0;
   my @chunklines;
   while(<$fh>){
         $i++;
      if (/^\s*```*\s*([\w|\.]+)\s*$/){
         die "Err: Another chunk is still unclosed" if $inchunk;
         $chunkstart = $1;
         $inchunk = 1;
         push @chunklines , [ START => $i, $1 ];
      }elsif (/^\s*```*/){
         if($chunkstart){
            $Chunks{$chunkstart} = [ @chunklines ];
         }else{
            die "Err: Chunk ending without a beginning"
         }
         undef $inchunk; undef $chunkstart;
         undef @chunklines;
      }elsif (/^\s*\#ifdef\s*(\w*)\s*$/){
         $in_ifdef = 1;
      }elsif (/^\s*\#endif\s*(\w*)\s*$/){
         undef $in_ifdef;
      }else{
         if($inchunk){
            unless($in_ifdef){
               if(/^(\s*)\@\{\s*([\w|\.]+)\s*\}\s*$/){
                  push @chunklines, [ LINK => $i, $2, scalar(split('', $1)) ]  
               }elsif(/^(\s*)\;(.*)$/){
                  # comments
                  push @chunklines, [ LNCMT => $i, $2, scalar(split('', $1)) ]  
               }else{
                  $_ =~/^(\s*)(.*)$/;
                  push @chunklines,  [ CHUNK => $i, $2, scalar(split('', $1)) ]  
               }
            }
         }

      }
   };
   my $block = $Chunks{$Target};
   $codeblock->($block, \%Chunks);
}

sub line_preprocess {
   my ($fh) = @_;

   my %Files;
   my %Chunks;

   my $filestart;
   my $chunkstart;
   my $inchunk = undef;
   my $ifdef_notmatch = undef;
   my $i = 0;
   my @chunklines;
   while(<$fh>){
         $i++;
      if (/^\s*```*\s*(\w+\.*\w+)\s*$/){
         die "Err: Another chunk is still unclosed" if $chunkstart;
         if($Target eq $1){
            $inchunk = 1;
         }
         $filestart = $1;
         undef $chunkstart;
      }elsif (/^\s*```*\s*(\w+)\s*$/){
         die "Err: Another chunk is still unclosed" if $filestart;
         if($Target eq $1){
            $inchunk = 1;
         }
         undef $filestart;
         $chunkstart = 1;
      }elsif (/^\s*```*/){
         undef $inchunk; undef $filestart; undef $chunkstart;
      }elsif (/^\s*\#ifdef\s*(\w*)\s*$/){
         if($CPP ne $1){
            $ifdef_notmatch = 1;
         }else{
            $ifdef_notmatch = undef;
         }
      }elsif (/^\s*\#endif\s*(\w*)\s*$/){
         exit unless($ifdef_notmatch);
      }else{
         if($inchunk){
            unless($ifdef_notmatch){
               print ";; dbg: $i";
               print "\n";
               print $_;
               print "\n";
            }
         }

      }
   };
}

sub main {
   open (my $fh, '<', $File) || die "Err: couldnt load file $File: $!";

#my ($Ext) = $Target =~ /(\.[^.]+)$/;
   if($CPP){
      line_preprocess $fh;
   }else{
      line_process $fh;
   }
}


sub make_string {
   my ($text, $instr) = @_;
   my $str = join "", @$text;
   undef @{$text};
   undef ${$instr};
   return  '"', $str , '"';
};
sub make_rex  {
   my ($text, $instr) = @_;
   my $str = join "", @$text;
   undef @{$text};
   undef ${$instr};
   return '(rex "', $str , '")';
};

my $Syn = {
   '"' => \&make_string,
   ' "' =>\&make_string,
   '#"' => \&make_rex,
};

$codeblock = sub {
   my ($Inblock, $chunks) = @_;

   my @Outblock = ();
   my $Instr = undef;

   my $Prev = ""; # because of multistring (rex) this is not linebased
   my $I = 0;
   my @Line = ();
   my @Word = (); # because (multi)string are also stored here

   my $pushline ; $pushline = sub {
      push @Line, join "", @Word if @Word;
      undef @Word;
      push @Line, " " . $_[0] . " " if $_[0];
   };

   foreach (@{ $Inblock } ) {

      $I++;

      my $wordcnt = 0;
      my $neo = undef;
      my $parcnt = 0;

      my ($leadws, $type, $line) = (0);
      if (ref $_ eq 'ARRAY'){
         ($type, $I, $line , $leadws) = @{$_};
         if($type eq 'CHUNK'){
            if( $Instr) {
               push @Word, "\n" . (' ' x $leadws) 
            } # continue ...
         }elsif(($type eq 'FILE') or ($type eq 'START')){
            push @Outblock,  ";\@dbg: $type"; 
            next; 
         }elsif($type eq 'LINK'){
            my $sublock = $chunks->{$line}; 
            $codeblock->($sublock, $chunks);
            next;
         }else{
            die 'todo for type: ' . $type;
         }
      }else{
         # user comments
         push @Outblock,  $_;
         next;
      }

      my $is_comment = 0;
      my @comment = '';
      foreach (split "", $line){
         if($Instr){
            ($_ eq '"') ?  push @Line,  $Instr->(\@Word,\$Instr ) : push @Word, $_ ;
         }else{
            if($is_comment){ push @comment, $_; next; }

            if($_ eq '"'){
               my $w = join "", @Word;
               my $syn = $Syn->{$w . $_};
               undef @Word;
               $Instr = ($syn) 
                  ? $syn 
                  : die "Err: invalid char befor doubleq: $Prev";
            }elsif($_ eq ';'){ #ignore
               $is_comment = 1;
            }elsif($_ eq "\n"){ #ignore
               $pushline->();
            }elsif($_ eq '|'){ #ignore
            }elsif($_ eq ')'){ 
               $neo = undef;
               $pushline->(')');
            }elsif($_ eq '('){ 
               if(@Word){
                  $neo = 1;
                  push @Line, '(';
                  $pushline->();
               }else{
                  push @Line, '(';
               }
            }elsif($_ eq ' '){ 
               $pushline->(' ');
            }elsif($_ eq '$'){ 
               $pushline->('(');
               $parcnt++;
            }elsif($_ eq '['){ 
               $pushline->('#(')
            }elsif($_ eq ']'){
               $pushline->(')')
            }elsif($_ eq '\\'){
               if($Prev eq '\\'){
                  pop @Line; # pop \, ignore '\'
                  $pushline->('(');
                  $parcnt++;
               }else{
                  $pushline->($_ )
               }
            }elsif($_ eq '>'){
               if($Prev eq '-'){
                  pop @Word; # pop -, ignore '>'
               }elsif($Prev eq '='){
                  pop @Word;
                  $pushline->(')(')

               }else{
                  $pushline->($_ )
               }
            }else{
               push @Word, $_ ;
            }
            $Prev = $_;
         }
      }

      if(not $Instr){
         my $line = join "", @Line if @Line;
         my $cmt = join "", @comment if @comment;

         if ($line ) {
            push @Outblock , [ CHUNK =>  $I, $line, $leadws, $parcnt, $cmt ] ;
         }else{
            if($cmt){
               push @Outblock, $cmt;
            }else{
               push @Outblock,  ";\@dbg:$I" ;
            }
         }
      }

      undef @Line;
   }
   parentize (\@Outblock);
};



sub parentize {
   my $inblock = shift;



   # fuck me
   #    harder

   my @outblock;

   my $_line = undef;
   my $_ws = 0;
   my $_parcnt = 0;

   my $_cmt = '';
   my @cmtbuf;

   my $addline ; $addline = sub {

   };

   my @indend_stack;

   my $calc_closers; $calc_closers = sub {
      my ($prevind, $closers)  = @_;
      
      my $ind = (@indend_stack) ? pop @indend_stack : 0;

      if ($prevind < $ind){
         print 'MM ' . $prevind;
         return $calc_closers->($prevind, $closers + 1)
      }elsif ($prevind > $ind){
         print 'PP ' . $prevind;
         push @indend_stack, $ind;
         return $closers 
      }else{
         return ($closers + 1);
         #return $closers;
      }
   };

   my ($type, $i, $line, $ws, $parcnt, $cmt ) = (0, 1, 2, 3, 4, 5) ;
   foreach (@{ $inblock } ){
      if(ref $_ eq 'ARRAY'){
         if(defined $_line){

            if($_->[$ws] > $_ws){
               if ($_line =~ /^\s*\(\s*$/){
                  push @outblock,  (' ' x $_ws ) . '(' 
               }else{
                  push @outblock,   ((' ' x $_ws ) . '(' . $_line) . ')' x $_parcnt;
               }
               push @indend_stack, $_ws;
            }elsif($_->[$ws] < $_ws){
               print  '#C '  . $_line  . Dumper @indend_stack;
               print '#II ' . $_->[$ws] . "\n";
               my $closers = $calc_closers->($_->[$ws], 0);
               print "\n## " . $closers .  ' ' .$_line . "\n";

               push @outblock, ($_line =~ /^\s*\(\s*$/)
                  ? (' ' x $_ws ) . '(' 
                  : ((' ' x $_ws ) . '(' . $_line) . ')' x (1 + $closers + $_parcnt);
            }else{
               push @outblock, ($_line =~ /^\s*\(\s*$/)
                  ? (' ' x $_ws ) .  '()' 
                  : ((' ' x $_ws ) . '(' . $_line) . ')' x ( $_parcnt + 1);
            }
         }else{
            # first line
         }
         ($_line, $_ws, $_parcnt, $_cmt) = ($_->[$line], $_->[$ws], $_->[$parcnt], $_->[$cmt]);
         if(@cmtbuf){
            my $wspace = ' ' x $_ws;
            push @outblock, $wspace . join "\n$wspace", @cmtbuf;
            undef @cmtbuf;
         }
      }else{
         push @cmtbuf, ' ' x $_ws  . $_;
      }

   }
   if(@cmtbuf){
      push @outblock, @cmtbuf ;
      undef @cmtbuf;
   }
   my $closers = scalar @indend_stack;
   push @outblock, ' ' x $_ws . '(' .  $_line . ')' x ($_parcnt + $closers + 1);
   print join "\n", @outblock;
}
main ();

