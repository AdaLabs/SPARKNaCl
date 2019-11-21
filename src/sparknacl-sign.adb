with SPARKNaCl.Utils;
with SPARKNaCl.Hashing;
package body SPARKNaCl.Sign
  with SPARK_Mode => On
is

   --============================================
   --  Local constants and types
   --============================================

   GF_D  : constant GF := (16#78a3#, 16#1359#, 16#4dca#, 16#75eb#,
                           16#d8ab#, 16#4141#, 16#0a4d#, 16#0070#,
                           16#e898#, 16#7779#, 16#4079#, 16#8cc7#,
                           16#fe73#, 16#2b6f#, 16#6cee#, 16#5203#);

   GF_I  : constant GF := (16#a0b0#, 16#4a0e#, 16#1b27#, 16#c4ee#,
                           16#e478#, 16#ad2f#, 16#1806#, 16#2f43#,
                           16#d7a7#, 16#3dfb#, 16#0099#, 16#2b4d#,
                           16#df0b#, 16#4fc1#, 16#2480#, 16#2b83#);

   GF_X  : constant GF := (16#d51a#, 16#8f25#, 16#2d60#, 16#c956#,
                           16#a7b2#, 16#9525#, 16#c760#, 16#692c#,
                           16#dc5c#, 16#fdd6#, 16#e231#, 16#c0a4#,
                           16#53fe#, 16#cd6e#, 16#36d3#, 16#2169#);

   GF_Y  : constant GF := (16#6658#, 16#6666#, 16#6666#, 16#6666#,
                           16#6666#, 16#6666#, 16#6666#, 16#6666#,
                           16#6666#, 16#6666#, 16#6666#, 16#6666#,
                           16#6666#, 16#6666#, 16#6666#, 16#6666#);

   --  RCC adds constant GF_XY
   GF_XY : constant GF := (16#DD90#, 16#A5B7#, 16#8AB3#, 16#6DDE#,
                           16#52F5#, 16#7751#, 16#9F80#, 16#20F0#,
                           16#E37D#, 16#64AB#, 16#4E8E#, 16#66EA#,
                           16#7665#, 16#D78B#, 16#5F0F#, 16#E787#);

   GF_D2 : constant GF := (16#f159#, 16#26b2#, 16#9b94#, 16#ebd6#,
                           16#b156#, 16#8283#, 16#149a#, 16#00e0#,
                           16#d130#, 16#eef3#, 16#80f2#, 16#198e#,
                           16#fce7#, 16#56df#, 16#d9dc#, 16#2406#);

   --  Original TweetNaCl code computes Q(3) by multiplying GF_X by GF_Y,
   --  but this is a constant (now called GF_XY), so that's used below.
   --
   --  We make this constant library-level to ensure that its declaration
   --  is only elaborated exactly once.
   type GF_Vector_4 is array (Index_4) of GF;

   Scalarbase_Q : constant GF_Vector_4 := (0 => GF_X,
                                           1 => GF_Y,
                                           2 => GF_1,
                                           3 => GF_XY);

   --============================================
   --  Local subprogram declarations
   --============================================

   --  Replaces function "add" in the TweetNaCl sources
   function "+" (Left  : in GF_Vector_4;
                 Right : in GF_Vector_4) return GF_Vector_4
     with Global => null;

   function Scalarmult (Q : in GF_Vector_4;
                        S : in Bytes_32) return GF_Vector_4
     with Global => null;

   function Scalarbase (S : in Bytes_32) return GF_Vector_4
     with Global => null;

   function Pack (P : in GF_Vector_4) return Bytes_32
     with Global => null;

   subtype Bit is Byte range 0 .. 1;

   function Par_25519 (A : in GF) return Bit
     with Global => null;

   function ModL (X : in I64_Seq_64) return Bytes_32
     with Global => null;

   --  RCC introduces this function to combine Hash and Reduce into
   --  a single call. Former procedure Reduce removed.
   function Hash_Reduce (M : in Byte_Seq) return Bytes_32
     with Global => null;

   procedure Unpackneg (R  :    out GF_Vector_4;
                        OK :    out Boolean;
                        P  : in     Bytes_32)
     with Global => null;

   --============================================
   --  Local subprogram bodies
   --============================================

   --  POK
   function "+" (Left  : in GF_Vector_4;
                 Right : in GF_Vector_4) return GF_Vector_4
   is
      A, B, C, D, E, F, G, H, T : GF;
   begin
      A := (Left (1) - Left (0)) * (Right (1) - Right (0));

      B := (Left (0) + Left (1)) * (Right (0) + Right (1));

      C := (Left (3) * Right (3)) * GF_D2;

      T := Left (2) * Right (2);
      D := T + T;

      E  := B - A;
      F  := D - C;
      G  := D + C;
      H  := B + A;

      return GF_Vector_4'(0 => E * F,
                          1 => H * G,
                          2 => G * F,
                          3 => E * H);
   end "+";

   function Scalarmult (Q : in GF_Vector_4;
                        S : in Bytes_32) return GF_Vector_4
   is
      CB     : Byte;
      Swap   : Boolean;
      LP, LQ : GF_Vector_4;

      --  RCC Remove formals for globals?
      procedure CSwap (P, Q : in out GF_Vector_4;
                       Swap : in     Boolean)
        with Global => null;

      --  POK
      procedure CSwap (P, Q : in out GF_Vector_4;
                       Swap : in     Boolean)
      is
      begin
         for I in Index_4 loop
            Utils.Sel_25519 (P (I), Q (I), Swap);
         end loop;
      end CSwap;

   begin
      LP := (0 => GF_0,
             1 => GF_1,
             2 => GF_1,
             3 => GF_0);
      LQ := Q;

      for I in reverse U32 range 0 .. 255 loop
         CB   := S (I32 (Shift_Right (I, 3)));
         Swap := Boolean'Val (Shift_Right (CB, Natural (I and 7)) mod 2);

         CSwap (LP, LQ, Swap);

         --  Note user-defined "+" for GF_Vector_4 called here
         LQ := LQ + LP;
         LP := LP + LP;
         CSwap (LP, LQ, Swap);
      end loop;

      return LP;
   end Scalarmult;


   --  POK
   function Scalarbase (S : in Bytes_32) return GF_Vector_4
   is
   begin
      return Scalarmult (Scalarbase_Q, S);
   end Scalarbase;

   --  POK
   function Par_25519 (A : in GF) return Bit
   is
      D : Bytes_32;
   begin
      D := Utils.Pack_25519 (A);
      return (D (0) mod 2);
   end Par_25519;

   --  POK
   function Pack (P : in GF_Vector_4) return Bytes_32
   is
      TX, TY, ZI : GF;
      R : Bytes_32;
   begin
      ZI := Utils.Inv_25519 (P (2));
      TX := P (0) * ZI;
      TY := P (1) * ZI;
      R := Utils.Pack_25519 (TY);
      R (31) := R (31) xor (Par_25519 (TX) * 128);
      return R;
   end Pack;

   L : constant I64_Seq_32 := (16#ed#, 16#d3#, 16#f5#, 16#5c#,
                               16#1a#, 16#63#, 16#12#, 16#58#,
                               16#d6#, 16#9c#, 16#f7#, 16#a2#,
                               16#de#, 16#f9#, 16#de#, 16#14#,
                               16#00#, 16#00#, 16#00#, 16#00#,
                               16#00#, 16#00#, 16#00#, 16#00#,
                               16#00#, 16#00#, 16#00#, 16#00#,
                               16#00#, 16#00#, 16#00#, 16#10#);

   function ModL (X : in I64_Seq_64) return Bytes_32
   is
      Carry : I64;
      XL    : I64_Seq_64 := X;
      R     : Bytes_32;
   begin
      for I in reverse I32 range 32 .. 63 loop
         Carry := 0;
         for J in I32 range (I - 32) .. (I - 13) loop
            XL (J) := XL (J) +
              Carry - 16 * XL (I) * L (J - (I - 32)); --  POV * 4
            Carry := ASR_8 (XL (J) + 128); --  POV on +
            XL (J) := XL (J) - (Carry * 256); --  POV on - and *
         end loop;
         XL (I - 12) := XL (I - 12) + Carry; --  POV on +
         XL (I) := 0;
      end loop;
      Carry := 0;

      for J in Index_32 loop
         XL (J) := XL (J) + (Carry - ASR_4 (XL (31)) * L (J)); -- POV * 3
         Carry := ASR_8 (XL (J));
         XL (J) := XL (J) mod 256;
      end loop;

      for J in Index_32 loop
         XL (J) := XL (J) - Carry * L (J); --  POV on -
      end loop;

      for I in Index_32 loop
         XL (I + 1) := XL (I + 1) + ASR_8 (XL (I)); --  POV on RHS 2nd +
         R (I) := Byte (XL (I) mod 256);
      end loop;
      return R;
   end ModL;

   --  POK
   function Hash_Reduce (M : in Byte_Seq) return Bytes_32
   is
      R : Hashing.Digest;
      X : I64_Seq_64;
   begin
      Hashing.Hash (R, M);
      for I in Index_64 loop
         X (I) := I64 (R (I));
      end loop;
      return ModL (X);
   end Hash_Reduce;


   --  POK
   procedure Unpackneg (R  :    out GF_Vector_4;
                        OK :    out Boolean;
                        P  : in     Bytes_32)
   is
      --  Local, time-constant equality test for GF
      --  In the original TweetNaCl sources, this is called eq25519
      function "=" (Left, Right : in GF) return Boolean
        with Global => null;

      function Pow_2523 (I : in GF) return GF
        with Global => null;

      --  POK
      function "=" (Left, Right : in GF) return Boolean
      is
      begin
         return Equal (Bytes_32'(Utils.Pack_25519 (Left)),
                       Bytes_32'(Utils.Pack_25519 (Right)));
      end "=";

      --  POK
      function Pow_2523 (I : in GF) return GF
      is
         C, C2 : GF;
      begin
         C := I;
         --  Note that 2**252 - 3 = 16#1111_1111 .. 1101#
         --  with only "bit 1" set to 0
         for A in reverse 0 .. 250 loop
            C2 := Square (C);
            if A = 1 then
               C := C2;
            else
               C := C2 * I;
            end if;
         end loop;
         return C;
      end Pow_2523;


      --  Note: refactoring here to functional/SSA form reduces the
      --  number of calls to "*" from 8 in the original TweetNaCl code
      --  to 5 from here until the initialization of R0, but only if
      --  "*" on GF is commutative.
      R1          : constant GF := Utils.Unpack_25519 (P);
      R2          :          GF renames GF_1;
      R1_Squared  : constant GF := Square (R1);
      Num         : constant GF := R1_Squared - R2;
      Den         : constant GF := R2 + (R1_Squared * GF_D);
      Den_Power_2 : constant GF := Square (Den);
      Den_Power_4 : constant GF := Square (Den_Power_2);
      Num_Den2    : constant GF := (Num * Den) * Den_Power_2;

      R0    : GF := Pow_2523 ((Den_Power_4 * Num_Den2)) * Num_Den2;
      Check : GF;
   begin
      Check := Square (R0) * Den;

      if Check /= Num then
         R0 := R0 * GF_I;
      end if;

      Check := Square (R0) * Den;

      if Check /= Num then
         R  := (others => GF_0);
         OK := False;
         return;
      end if;

      if Par_25519 (R0) = (P (31) / 128) then
         R0 := GF_0 - R0;
      end if;

      R := (0 => R0,
            1 => R1,
            2 => R2,
            3 => R0 * R1);
      OK := True;
   end Unpackneg;



   --============================================
   --  Exported subprogram bodies
   --============================================

   function Serialize (K : in Signing_SK) return Bytes_64
   is
   begin
      return K.F;
   end Serialize;

   function Serialize (K : in Signing_PK) return Bytes_32
   is
   begin
      return K.F;
   end Serialize;

   procedure Sanitize (K : out Signing_PK)
   is
   begin
      SPARKNaCl.Sanitize (K.F);
   end Sanitize;

   procedure Sanitize (K : out Signing_SK)
   is
   begin
      SPARKNaCl.Sanitize (K.F);
   end Sanitize;




   --  POK
   procedure Keypair (PK : out Signing_PK;
                      SK : out Signing_SK)
   is
      D   : Bytes_64;
      LPK : Bytes_32;
      RB  : Bytes_32;
   begin
      RB  := Utils.Random_Bytes_32;

      Hashing.Hash (D, RB);
      D (0)  := D (0) and 248;
      D (31) := (D (31) and 127) or 64;

      LPK := Pack (Scalarbase (D (0 .. 31)));

      PK.F := LPK;
      SK.F := RB & LPK;

      --  Sanitize intermediate values used in key generation
      pragma Warnings (GNATProve, Off, "statement has no effect");
      Sanitize (RB);
      Sanitize (D);
      Sanitize (LPK);
      pragma Unreferenced (RB);
      pragma Unreferenced (D);
      pragma Unreferenced (LPK);
   end Keypair;

   procedure Sign (SM :    out Byte_Seq;
                   M  : in     Byte_Seq;
                   SK : in     Signing_SK)
   is
      D    : Bytes_64;
      H, R : Bytes_32;
      X    : I64_Seq_64;
   begin
      Hashing.Hash (D, Serialize (SK) (0 .. 31));
      D (0)  := D (0) and 248;
      D (31) := D (31) and 127;
      D (31) := D (31) or 64;

      SM := (others => 0);
      SM (64 .. SM'Last) := M;
      SM (32 .. 63) := D (32 .. 63);

      R := Hash_Reduce (SM (32 .. SM'Last));

      SM (0 .. 31) := Pack (Scalarbase (R));

      SM (32 .. 63) := Serialize (SK) (32 .. 63);

      H := Hash_Reduce (SM);

      X := (others => 0);
      for I in Index_32 loop
         X (I) := I64 (R (I));
      end loop;

      for I in Index_32 loop
         for J in Index_32 loop
            X (I + J) := X (I + J) +  --  POV on RHS +
              I64 (U64 (H (I)) * U64 (D (J)));
         end loop;
      end loop;

      SM (32 .. 63) := ModL (X);

      --  RCC - Sanitize D, H, R and X here? Not clear if these values
      --  are sensitive.
   end Sign;

   --  POK
   procedure Open (M      :    out Byte_Seq;
                   Status :    out Boolean;
                   MLen   :    out I32;
                   SM     : in     Byte_Seq;
                   PK     : in     Signing_PK)
   is
      T    : Bytes_32;
      P, Q : GF_Vector_4;
      LN   : I32;
   begin
      MLen := -1;
      if SM'Length < 64 then
         M := (others => 0);
         Status := False;
         return;
      end if;

      Unpackneg (Q, Status, Serialize (PK));
      if not Status then
         M := (others => 0);
         return;
      end if;

      M := SM; -- precondition ensures lengths match
      M (32 .. 63) := Serialize (PK);

      P := Scalarmult (Q, Hash_Reduce (M));
      Q := Scalarbase (SM (32 .. 63));
      --  Call to user-defined "+" for GF_Vector_4
      T := Pack (P + Q);

      if not Equal (SM (0 .. 31), T) then
         M := (others => 0);
         Status := False;
         return;
      end if;

      LN := I32 (I64 (SM'Length) - 64);

      M (0 .. LN - 1) := SM (64 .. LN + 63);
      MLen := LN;
      Status := True;

      --  RCC - Sanitize D, H, R and X here? Not clear if these values
      --  are sensitive.
   end Open;

end SPARKNaCl.Sign;
