with SPARKNaCl.Utils;
with SPARKNaCl.Scalar;
with SPARKNaCl.Secretbox;

package body SPARKNaCl.Cryptobox
  with SPARK_Mode => On
is
   --  POK
   procedure Keypair (PK : out Public_Key;
                      SK : out Secret_Key)
   is
      Raw_SK : Bytes_32 := Utils.Random_Bytes_32;
   begin
      SK.F := Raw_SK;
      PK.F := Scalar.Mult_Base (Raw_SK);

      pragma Warnings (GNATProve, Off, "statement has no effect");
      Sanitize (Raw_SK);
      pragma Unreferenced (Raw_SK);
   end Keypair;

   --  POK
   function Construct (K : in Bytes_32) return Secret_Key
   is
   begin
      return Secret_Key'(F => K);
   end Construct;

   --  POK
   function Construct (K : in Bytes_32) return Public_Key
   is
   begin
      return Public_Key'(F => K);
   end Construct;

   --  POK
   function Serialize (K : in Secret_Key) return Bytes_32
   is
   begin
      return K.F;
   end Serialize;

   --  POK
   function Serialize (K : in Public_Key) return Bytes_32
   is
   begin
      return K.F;
   end Serialize;

   --  POK
   procedure Sanitize (K : out Secret_Key)
   is
   begin
      Sanitize (K.F);
   end Sanitize;

   --  POK
   procedure Sanitize (K : out Public_Key)
   is
   begin
      Sanitize (K.F);
   end Sanitize;

   --  POK
   procedure BeforeNM (K  :    out Core.Salsa20_Key;
                       PK : in     Public_Key;
                       SK : in     Secret_Key)
   is
      S  : Bytes_32;
      LK : Bytes_32;
   begin
      S := Scalar.Mult (SK.F, PK.F);
      Core.HSalsa20 (Output => LK,
                     Input  => Zero_Bytes_16,
                     K      => Core.Construct (S),
                     C      => Sigma);
      Core.Construct (K, LK);

      --  RCC - Sanitize S and LK here? Not clear if these values are
      --  sensitive.
   end BeforeNM;

   --  POK
   procedure AfterNM (C      :    out Byte_Seq;
                      Status :    out Boolean;
                      M      : in     Byte_Seq;
                      N      : in     Stream.HSalsa20_Nonce;
                      K      : in     Core.Salsa20_Key)
   is
   begin
      Secretbox.Create (C, Status, M, N, K);
   end AfterNM;

   --  POK
   procedure Open_AfterNM
     (M      :    out Byte_Seq; --  Output plaintext
      Status :    out Boolean;
      C      : in     Byte_Seq; --  Input ciphertext
      N      : in     Stream.HSalsa20_Nonce;
      K      : in     Core.Salsa20_Key)
   is
   begin
      Secretbox.Open (M, Status, C, N, K);
   end Open_AfterNM;

   --  POK
   procedure Create (C            :    out Byte_Seq;
                     Status       :    out Boolean;
                     M            : in     Byte_Seq;
                     N            : in     Stream.HSalsa20_Nonce;
                     Recipient_PK : in     Public_Key;
                     Sender_SK    : in     Secret_Key)
   is
      K : Core.Salsa20_Key;
   begin
      BeforeNM (K, Recipient_PK, Sender_SK);
      AfterNM (C, Status, M, N, K);

      --  RCC - Sanitize K here? Not clear if this value is
      --  sensitive.
   end Create;

   --  POK
   procedure Open (M            :    out Byte_Seq;
                   Status       :    out Boolean;
                   C            : in     Byte_Seq;
                   N            : in     Stream.HSalsa20_Nonce;
                   Sender_PK    : in     Public_Key;
                   Recipient_SK : in     Secret_Key)
   is
      K : Core.Salsa20_Key;
   begin
      BeforeNM (K, Sender_PK, Recipient_SK);
      Open_AfterNM (M, Status, C, N, K);

      --  RCC - Sanitize K here? Not clear if this value is
      --  sensitive.
   end Open;

end SPARKNaCl.Cryptobox;
