/******************************************************************************
Written and Copyright (C) by Dirk Klose
and the EmSec Embedded Security group of Ruhr-Universitaet Bochum.
All rights reserved.

Contact lightweight@crypto.rub.de for comments & questions.
This program is free software; You may use it or parts of it or
modifiy it under the following terms:

(1) Usage and/or redistribution and/or modification of the software
or parts of the software is permitted for non-commercial use only.

(2a) If this software or parts are used as part of a new software, you
must license the entire work, as a whole, under this License to anyone
who comes into possession of a copy. This License will therefore
apply, to the whole of the work, and all its parts, regardless of how
they are packaged.

(2b) You may expand this license by your own license. In this case this
license still applies to the software as mentioned in (2a) and must
not be changed. The expansion must be clearly recognizable as such. In
any case of collision between the license and the expansion the
license is superior to the expansion.

(3) If this software or parts are used as part of a new software, you
must provide equivalent access to the source code of the entire work,
as a whole, to anyone who comes into possession of a copy, in the same
way through the same place at no further charge, as for the binary
version.

(4) This program is distributed in the hope that it will be useful,
but   WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
(5) These notices must be retained in any copies of any part of this
documentation and/or software.

(6) If this software is used credit must be given to the
"Embedded Security Group of Ruhr-Universitaet Bochum, Germany" as
the authors of the parts of the software used. This can be in the form
of a textual message at program startup or  at *beginning* of the
documentation (online or textual) provided with the package.

If you are interested in a commercial use
please contact '''lightweigth@crypto.rub.de'''
******************************************************************************/

#include<stdio.h>

#include"decryption_4bit.inc"

#define high1_64(h1in) 			( (unsigned __int64)h1in >> 63 )	//msb as lsb
#define high4_64(h4in) 			( (unsigned __int64)h4in >> 60 )	//4 msb as lsb
#define rotate1l_64(r1lin)	 ( high1_64(r1lin) | ( r1lin << 1 ) )	//input rotated left (1x)
#define rotate4l_64(r4lin)	 ( high4_64(r4lin) | ( r4lin << 4 ) )	//input rotated left (4x)

void main(void)
{
//	Input values
	unsigned __int64 state=0x0;
	unsigned __int64 keyhigh=0x0;
	unsigned __int64 keylow=0x0;
//	Counter
	int i=1;
//	Variables sBox
	unsigned __int16 sBoxValue;
	int sBoxNr=0;
//	Variables pLayer
	unsigned __int64 temp;
//  Variables key scheduling
	unsigned __int64 subkey[32];
	int keyindex;
	int eingabe;
	printf("0 für enc, 1 für dec");
	scanf("%d",&eingabe);
	if(eingabe == 0)
	{
//	****************** Key Scheduling **********************
		for(int round=0;round<32;round++)
		{
			subkey[round] = keyhigh;							//61-bit left shift
			temp = keyhigh;
			keyhigh <<= 61;
			keyhigh |= (keylow<<45);
			keyhigh |= (temp>>19);
			keylow = (temp>>3)&0xFFFF;

			temp = keyhigh>>60;									//S-Box application
			keyhigh &=	0x0FFFFFFFFFFFFFFF;
			temp = sBox4[temp];
			keyhigh |= temp<<60;

			keylow ^= ( ( (round+1) & 0x01 ) << 15 );			//round counter addition
			keyhigh ^= ( (round+1) >> 1 );
		}
//	****************** End Key Scheduling ******************
//	****************** Encryption **************************
		for(i=0;i<31;i++)
		{
//	****************** addRoundkey *************************
			state ^= subkey[i];
//	****************** End addRoundkey *********************
//	****************** sBoxLayer ***************************
			for(sBoxNr=0;sBoxNr<16;sBoxNr++)
			{
				sBoxValue = state & 0xF;						//get lowest nibble
				state &=	0xFFFFFFFFFFFFFFF0;					//kill lowest nibble
				state |=	sBox4[sBoxValue];					//put new value to lowest nibble (sBox)
				state = rotate4l_64(state);						//next(rotate by one nibble)
			}
//	****************** End sBoxLayer ***********************
//	****************** pLayer ******************************
			temp = 0;
			for(int k=0;k<64;k++)
			{
				int position = (16*k) % 63;						//Arithmentic calculation of the p-Layer
				if(k == 63)										//Exception for bit 63
					position = 63;
				temp |= ((state>>k) & 0x1) << position;			//result writing
			}
			state=temp;
//	****************** End pLayer **************************
		}
//	****************** addRoundkey (Round 31) **************
		state ^= subkey[31];
//	****************** End addRoundkey (Round 31) **********
	}
//	****************** End Encryption **********************
	else if(eingabe == 1)
	{
		for(int round=0;round<32;round++)
		{
			subkey[round] = keyhigh;							//61-bit left shift
			temp = keyhigh;
			keyhigh <<= 61;
			keyhigh |= (keylow<<45);
			keyhigh |= (temp>>19);
			keylow = (temp>>3)&0xFFFF;

			temp = keyhigh>>60;									//S-Box application
			keyhigh &=	0x0FFFFFFFFFFFFFFF;
			temp = sBox4[temp];
			keyhigh |= temp<<60;

			keylow ^= ( ( (round+1) & 0x01 ) << 15 );			//round counter addition
			keyhigh ^= ( (round+1) >> 1 );
		}
//	****************** End Key Scheduling ******************
//	****************** Decryption **************************
		keyindex = 31;
		for(i=0;i<31;i++)
		{
//	****************** addRoundkey *************************
			state ^= subkey[keyindex];
			keyindex--;
//	****************** End addRoundkey *********************
//	****************** pLayer ******************************
			temp = 0;
			for(int k=0;k<64;k++)
			{
				int position = (4*k) % 63;						//Arithmentic calculation of the p-Layer
				if(k == 63)										//Exception for bit 63
					position = 63;
				temp |= ((state>>k) & 0x1) << position;			//result writing
			}
			state=temp;
//	****************** End pLayer **************************
//	****************** sBoxLayer ***************************
			for(sBoxNr=0;sBoxNr<16;sBoxNr++)
			{
				sBoxValue = state & 0xF;						//get lowest nibble
				state &=	0xFFFFFFFFFFFFFFF0;					//kill lowest nibble
				state |=	invsBox4[sBoxValue];				//put new value to lowest nibble (sbox)
				state = rotate4l_64(state);						//next(rotate by one nibble)
			}
//	****************** End sBoxLayer ***********************
		}
//	****************** addRoundkey (Round 31) **************
		state ^= subkey[0];
//	****************** End addRoundkey (Round 31) **********
	}
//	****************** End Decryption **********************
}
