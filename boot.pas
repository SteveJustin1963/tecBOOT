{Pascal Source control lpt port}

program bootZ80;        { Z80 Bootloader. Uses NMI, RESET, CLOCK, A15   }

uses crt;               { Copyright (c) 1998, Jens Dyekjær Madsen - V16 }

const

  ram  = 2048;          { Size of RAM   - Adjust if more ram!   }

  frq  = 4000000;       { Clockfrequence                        }

var

  lptadr: array[1..4] of word absolute 0:$408;          { LPT port table}

  lptbase: word;

  tick: integer absolute 0:$46c;                        { Timer counter }

const

  set0 = 12;            { Swap 0 into H }

  set1 = 20;            { Swap 1 into H }

  readv= 47;            { Read (DE) to H}

  load = 28;            { Load DE = HL  }

  loadl= 74;            { Set L = H     }

  init = 85;            { Init          }

  prog = 108;           { (DE) = H, DE++}

  readbit1 = 56;        { Read bit 7,H  }

  readbit2 = 66;        { Readbit end   }



  boot: array[$00..$0D] of word =

  ( $067,       {0000   00+4:           LD      H,A     ;67 00       : 8}

    $087,       {0002   08+4:   SET0    ADD     A,A     ;87 00       : 8}

    $080,       {0004   16+4:   SET1    ADD     A,B     ;80 00       : 8}

    $0EB,       {0006   24+4:   LOAD    EX      DE,HL   ;EB 00       : 8}

    $07E,       {0008   32+7:           LD      A,(HL)  ;7E 00       :11}

    $0EB,       {000A   43+4:   READV   EX      DE,HL   ;EB 00       : 8}

    $07E,       {000C   51+7:   RDBIT   LD      A,(HL)  ;7E 00       :11}

    $07C,       {000E   62+4:   RDBIT2  LD      A,H     ;7C 00       : 8}

    $06C,       {0010   70+4:   LOADL   LD      L,H     ;6C 00       : 8}

    $106,       {0012   78+7:   INIT    LD      B,1     ;06 01       : 7}

    $112,$100,  {0014   85+7:   PGM     LD      (DE),A  ;12 01 00 01 :17}

    $113,$100); {0018   102+6:  PROG    INC     DE      ;13 01 00 01 :16}



procedure clk(n:longint; v1,v2: byte);  { Toggle v1 and v2 n times (lpt)}

var

  i: longint;

begin

  for i:=1 to n do                              { Toggle n times        }

  begin

    port[lptbase]:=v1;                          { Send V1 to lpt port   }

    port[lptbase]:=v2;                          { Send V2 to port       }

  end;

end;



procedure run(t: integer; v1,v2: byte);

begin

  port[lptbase]:=v1;                            { Send V1 to lpt port   }

  t:=t+tick+1;                                  { End time              }

  repeat until t-tick<0;                        { Wait time             }

  port[lptbase]:=v2;                            { Send V2 to lpt port   }

end;



procedure cmd(n: integer);                      { Command on Z80        }

begin

  clk(2,2,3);                                   { reset                 }

  clk(n+4,6,7);                                 { Step to executed      }

end;



function rdbit: byte;                           { Read high bit on Z80  }

begin

  cmd(readbit1);                                { Execute command       }

  rdbit:=1-(port[succ(lptbase)] shr 7);         { Read BUSY             }

  clk(readbit2-readbit1,6,7);                   { End command           }

end;



procedure initz80;                              { Clear and init z80    }

var

  i: integer;

  osc: boolean;                         { External Oscilator            }

procedure send(v: word);                { Push data on stack            }

begin

  clk(longint(v)*4,6,7);                { Instructions before NMI       }

  clk(1,5,7);                           { NMI                           }

  clk(15,6,7);                          { 11 cycles + 4                 }

end;

begin

  osc:=(port[$379]  and $40 = 0);

  writeln('Oscilator: ',osc);



  writeln('Erasing');

  clk(16,2,3);                          { reset                         }

  if osc then

    run(((longint(ram)*49)*19)div frq,$D,7)             { Fill 0067h    }

  else

    clk(longint(ram)*49,4,7);           { Fill 0067h, >49 cycles / byte }



  clk(16,2,3);                          { reset                         }

  send($67);                            { NMI                           }



  writeln('Setup SP');

  send($404-$67);                               { $4 = INC B, 4 cycles  }

  send($231-$67);                               { LD SP, 0402H          }



  if osc then

    run(((longint(ram)*4+6)*19)div frq,$F,7)    { Set stack pointer     }

  else

    clk(longint(ram)*4+6,6,7);                  { Go, > 4*ram+6 cycles  }



  clk(16,2,3);                                  { reset                 }



  writeln('Address $1c');

  clk(15*($402-$1c)DIV 2,4,7);                  { NMI until SP at $1C   }

  clk(2,6,7);



  writeln('Load bootloader');

  for i:=$0d downto $00 do send(boot[i]-$67);   { Load bootload code    }

  writeln('Bootloader ok');



  cmd(init);                                    { Initialize cmd to z80 }

end;





function rdval: byte;

var

  i,j: byte;

begin

  j:=0;                                         { Reset value   }

  for i:=1 to 8 do                              { Read 8 bits   }

  begin

    j:=j+j+rdbit;                               { Get value     }

    cmd(set0);                                  { Next bit      }

  end;

  rdval:=j;                                     { Return byte   }

end;



procedure setval(v: byte);

var

  i: byte;

begin

  for i:=7 downto 0 do if (v shr i) and 1=1 then cmd(set1) else cmd(set0);

end;



procedure setadr(adr: word);

begin

  setval(lo(adr));

  cmd(loadl);

  setval(hi(adr));

  cmd(load);

end;



type

  chr2 = array[1..2] of char;

const

  hexd: array[0..$f] of char =

    ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');

var

  hexb: array[byte] of chr2;



procedure hexinit;

var

  h: chr2;

  i: byte;

begin

  for i:=0 to 255 do

  begin

    h[1]:=hexd[i shr 4];

    h[2]:=hexd[i and $f];

    hexb[i]:=h;

  end;

end;



var

  s: string;

  m: word;

  adr: word;

  i: word;

  j: byte;

  k,l: word;



begin

  hexinit;                                      { Initializes hex array }

  lptbase:=lptadr[1];                           { Setup LPT base address}

  initz80;                                      { Clear and init z80    }



{ Check register }

  setval($4a);

  writeln('Check setval: ',hexb[rdval]);



{ Store message at $c0 }

  s:='Hello, Z80 is on';

  setadr($C0);

  for i:=1 to length(s) do

  begin

    setval(ord(s[i]));

    cmd(prog);

  end;



  writeln('HEX data:');

  for i:=0 to $f do

  begin

    write(hexb[i],'0: ');

    for j:=0 to $f do

    begin

      setadr(j+i shl 4);

      cmd(readv);

      write(hexb[rdval],' ');

    end;

    writeln;

  end;

end.

