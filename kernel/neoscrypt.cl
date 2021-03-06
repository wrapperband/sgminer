#define SALSA_SMALL_UNROLL 3
#define CHACHA_SMALL_UNROLL 3

// If SMALL_BLAKE2S is defined, BLAKE2S_UNROLL is interpreted
// as the unroll factor; must divide cleanly into ten.
// Usually a bad idea.
// #define SMALL_BLAKE2S
// #define BLAKE2S_UNROLL 5

#define BLOCK_SIZE           64U
#define FASTKDF_BUFFER_SIZE 256U
#ifndef PASSWORD_LEN
#define PASSWORD_LEN         80U
#endif

#if !defined(cl_khr_byte_addressable_store)
#error "Device does not support unaligned stores"
#endif

void CopyBytes(void *restrict dst, const void *restrict src, uint len)
{
    for(int i = 0; i < len; ++i)
		((uchar *)dst)[i] = ((uchar *)src)[i];
}

void CopyBytes32(void *restrict dst, const void *restrict src)
{
   	#pragma unroll 4
    for(int i = 31; i > 0; i-=8) 
    {
    		((uchar *)dst)[i] = ((uchar *)src)[i];    
    		((uchar *)dst)[i-1] = ((uchar *)src)[i-1];
    		((uchar *)dst)[i-2] = ((uchar *)src)[i-2];
    		((uchar *)dst)[i-3] = ((uchar *)src)[i-3];
    		((uchar *)dst)[i-4] = ((uchar *)src)[i-4];
    		((uchar *)dst)[i-5] = ((uchar *)src)[i-5];
    		((uchar *)dst)[i-6] = ((uchar *)src)[i-6];    
    		((uchar *)dst)[i-7] = ((uchar *)src)[i-7];
    } 
}

void CopyBytes64(void *restrict dst, const void *restrict src)
{
	#pragma unroll 8
    for(int i = 63; i > 0; i-=8) 
    {
  		((uchar *)dst)[i] = ((uchar *)src)[i];    
  		((uchar *)dst)[i-1] = ((uchar *)src)[i-1];
  		((uchar *)dst)[i-2] = ((uchar *)src)[i-2];
  		((uchar *)dst)[i-3] = ((uchar *)src)[i-3];
  		((uchar *)dst)[i-4] = ((uchar *)src)[i-4];
  		((uchar *)dst)[i-5] = ((uchar *)src)[i-5];
  		((uchar *)dst)[i-6] = ((uchar *)src)[i-6];    
  		((uchar *)dst)[i-7] = ((uchar *)src)[i-7];
    } 
}


void XORBytesInPlace(void *restrict dst, const void *restrict src, uchar bufidx)
{
  switch( bufidx & 0x03)
  {
  case 0:
    #pragma unroll 2
    for(int i = 0; i < 4; i+=2)
    {       
    	  ((uint2 *)dst)[i] ^= ((uint2 *)src)[i];       
    	  ((uint2 *)dst)[i+1] ^= ((uint2 *)src)[i+1]; 
    }
    break;  

  case 2:  
    #pragma unroll 8
    for(int i = 0; i < 16; i+=2)
    {
    	  ((uchar2 *)dst)[i] ^= ((uchar2 *)src)[i]; 
    	  ((uchar2 *)dst)[i+1] ^= ((uchar2 *)src)[i+1]; 
    }
    break;


  default:
  #pragma unroll 8
   for(int i = 0; i < 32; i+=4)
   {
  	  ((uchar *)dst)[i] ^= ((uchar *)src)[i];
  	  ((uchar *)dst)[i+1] ^= ((uchar *)src)[i+1];
  	  ((uchar *)dst)[i+2] ^= ((uchar *)src)[i+2];
  	  ((uchar *)dst)[i+3] ^= ((uchar *)src)[i+3];   
    }
  }
} 

void XORBytes(void *restrict dst, const void *restrict src1, const void *restrict src2, uint len)
{
	#pragma unroll 1
	for(int i = 0; i < len; ++i)
		((uchar *)dst)[i] = ((uchar *)src1)[i] ^ ((uchar *)src2)[i];
}


// Blake2S

#define BLAKE2S_BLOCK_SIZE    64U
#define BLAKE2S_OUT_SIZE      32U
#define BLAKE2S_KEY_SIZE      32U

static const __constant uint BLAKE2S_IV_1[16] =
{
    0x6B08C647, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E523F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
};

static const __constant uint BLAKE2S_IV_2[8] =
{
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E52FF, 0x9B05688C, 0xE07C2654, 0x5BE0CD19
};

static const __constant uchar BLAKE2S_SIGMA[10][16] =
{
    {  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15 } ,
    { 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3 } ,
    { 11,  8, 12,  0,  5,  2, 15, 13, 10, 14,  3,  6,  7,  1,  9,  4 } ,
    {  7,  9,  3,  1, 13, 12, 11, 14,  2,  6,  5, 10,  4,  0, 15,  8 } ,
    {  9,  0,  5,  7,  2,  4, 10, 15, 14,  1, 11, 12,  6,  8,  3, 13 } ,
    {  2, 12,  6, 10,  0, 11,  8,  3,  4, 13,  7,  5, 15, 14,  1,  9 } ,
    { 12,  5,  1, 15, 14, 13,  4, 10,  0,  7,  6,  3,  9,  2,  8, 11 } ,
    { 13, 11,  7, 14, 12,  1,  3,  9,  5,  0, 15,  4,  8,  6,  2, 10 } ,
    {  6, 15, 14,  9, 11,  3,  0,  8, 12,  2, 13,  7,  1,  4, 10,  5 } ,
    { 10,  2,  8,  4,  7,  6,  1,  5, 15, 11,  9, 14,  3, 12, 13 , 0 } ,
};


#define BLAKE_G(idx0, idx1, a, b, c, d, key)	do { \
  for(int i=0; i< 2; ++i) {\
  a += b + key[BLAKE2S_SIGMA[idx0][idx1 + i]]; \
  d = rotate(d ^ a, ( i << 3 )+16U ); \
	c += d; \
	b = rotate(b ^ c, ( i + (i<<2))+20U) ; \
  }\
} while(0)


void Blake2S(uint *restrict inout, const uint *restrict inkey)
{
	uint16 V;
	uint8 tmpblock;
 
	// Load first block (IV into V.lo) and constants (IV into V.hi)
	V = vload16(0U, BLAKE2S_IV_1);
  tmpblock = V.lo; 

	// Compress state, using the key as the key

	#ifdef SMALL_BLAKE2S
	#pragma unroll BLAKE2S_UNROLL
	#else
	#pragma unroll 10
	#endif

      for(int x = 0; x < 10; ++x)
    	{
    		BLAKE_G(x, 0x00, V.s0, V.s4, V.s8, V.sc, inkey);
    		BLAKE_G(x, 0x02, V.s1, V.s5, V.s9, V.sd, inkey);
    		BLAKE_G(x, 0x04, V.s2, V.s6, V.sa, V.se, inkey);
    		BLAKE_G(x, 0x06, V.s3, V.s7, V.sb, V.sf, inkey);	
        BLAKE_G(x, 0x08, V.s0, V.s5, V.sa, V.sf, inkey);
    		BLAKE_G(x, 0x0A, V.s1, V.s6, V.sb, V.sc, inkey);
    		BLAKE_G(x, 0x0C, V.s2, V.s7, V.s8, V.sd, inkey);
    		BLAKE_G(x, 0x0E, V.s3, V.s4, V.s9, V.se, inkey);
     	}
    
    	// XOR low part of state with the high part,
    	// then with the original input block.
    	tmpblock = V.lo = V.lo ^ V.hi ^ tmpblock;
    
    	// Load constants (IV into V.hi)
    	V.hi = vload8(0U, BLAKE2S_IV_2);

	// Compress block, using the input as the key
	#ifdef SMALL_BLAKE2S
	#pragma unroll BLAKE2S_UNROLL
	#else
	#pragma unroll 10
	#endif
	for(int x = 0; x < 10; x++)
	{
		BLAKE_G(x, 0x00, V.s0, V.s4, V.s8, V.sc, inout);
		BLAKE_G(x, 0x02, V.s1, V.s5, V.s9, V.sd, inout);
		BLAKE_G(x, 0x04, V.s2, V.s6, V.sa, V.se, inout);
		BLAKE_G(x, 0x06, V.s3, V.s7, V.sb, V.sf, inout);
		BLAKE_G(x, 0x08, V.s0, V.s5, V.sa, V.sf, inout);
		BLAKE_G(x, 0x0A, V.s1, V.s6, V.sb, V.sc, inout);
		BLAKE_G(x, 0x0C, V.s2, V.s7, V.s8, V.sd, inout);
		BLAKE_G(x, 0x0E, V.s3, V.s4, V.s9, V.se, inout);
	}

	// Store result in input/output buffer
	vstore8(V.lo ^ V.hi ^ tmpblock, 0, inout);
}


/* FastKDF, a fast buffered key derivation function:
 * FASTKDF_BUFFER_SIZE must be a power of 2;
 * password_len, salt_len and output_len should not exceed FASTKDF_BUFFER_SIZE;
 * prf_output_size must be <= prf_key_size; */
void fastkdf(const uchar *restrict password, const uchar *restrict salt, const uint salt_len, uchar *restrict output, uint output_len)
{

	/*                    WARNING!
	 * This algorithm uses byte-wise addressing for memory blocks.
	 * Or in other words, trying to copy an unaligned memory region
	 * will significantly slow down the algorithm, when copying uses
	 * words or bigger entities. It even may corrupt the data, when
	 * the device does not support it properly.
	 * Therefore use byte copying, which will not the fastest but at
	 * least get reliable results. */

	// BLOCK_SIZE            64U
	// FASTKDF_BUFFER_SIZE  256U
	// BLAKE2S_BLOCK_SIZE    64U
	// BLAKE2S_KEY_SIZE      32U
	// BLAKE2S_OUT_SIZE      32U

  uchar bufidx = 0;
  uint8 Abuffer[9], Bbuffer[9] = { (uint8)(0) };
	uchar *A = (uchar *)Abuffer, *B = (uchar *)Bbuffer;
  uint i;
  
	// Initialize the password buffer
  #pragma unroll 5
  for( i = 0; i < 5; i++ )
      ((ulong2 *)A)[i] = ((ulong2 *)A)[i+5] = ((ulong2 *)A)[i+10] = ((ulong2 *)password)[i];   
  ((ulong2 *)A)[15] = ((ulong2 *)password)[0];
 
	((ulong8 *)(A + FASTKDF_BUFFER_SIZE))[0] = ((ulong8 *)password)[0];

	// Initialize the salt buffer
	if( !(salt_len ^ FASTKDF_BUFFER_SIZE))
	{
		((ulong16 *)B)[0] = ((ulong16 *)B)[2] = ((ulong16 *)salt)[0];
		((ulong16 *)B)[1] = ((ulong16 *)B)[3] = ((ulong16 *)salt)[1];
	}
	else
	{
		// salt_len is 80 bytes here

		#pragma unroll 5 	
    for( i = 0; i < 5; i++)
       ((ulong2 *)B)[i] = ((ulong2 *)B)[i+5] = ((ulong2 *)B)[i+10] = ((ulong2 *)salt)[i];
    ((ulong2 *)B)[15] = ((ulong2 *)salt)[0];

//		for(int i = 0; i < (FASTKDF_BUFFER_SIZE >> 3); ++i) ((ulong *)B)[i] = ((ulong *)salt)[i % 10];

		// Initialized the rest to zero earlier
      ((ulong8 *)(B + FASTKDF_BUFFER_SIZE))[0] = ((ulong8 *)salt)[0];
      ((ulong2 *)(B + FASTKDF_BUFFER_SIZE))[4] = ((ulong2 *)salt)[4];
	}

		// Make the key buffer twice the size of the key so it fits a Blake2S block
		// This way, we don't need a temp buffer in the Blake2S function.
		uchar input[BLAKE2S_BLOCK_SIZE], key[BLAKE2S_BLOCK_SIZE] = { 0 };    

    // The primary iteration
    #pragma unroll 1
    for(i = 0; i < 32; ++i)
    {   
    		// Copy input and key to their buffers
    		CopyBytes64(input, A + bufidx); 
        CopyBytes32(key, B + bufidx);

            // PRF
            Blake2S((uint *)input, (uint *)key);
    
            // Calculate the next buffer pointer
    
        bufidx = 0;   
        #pragma unroll 2
        for(int k = 0; k < 31; k+=16) {
          bufidx += input[k] + input[k+1] + input[k+2] + input[k+3] + input[k+4] + input[k+5] + input[k+6] + input[k+7];         
    			bufidx += input[k+8] + input[k+9] + input[k+10] + input[k+11] + input[k+12] + input[k+13] + input[k+14] + input[k+15]; 
        }    // Modify the salt buffer
    	      
        XORBytesInPlace(B + bufidx, input, bufidx );

    		if(  bufidx < BLAKE2S_KEY_SIZE )
    		{
    			// Head modified, tail updated
    			CopyBytes(B + FASTKDF_BUFFER_SIZE + bufidx, B + bufidx, BLAKE2S_KEY_SIZE - bufidx );
    		}
//    		else if( (FASTKDF_BUFFER_SIZE - bufidx ) < BLAKE2S_OUT_SIZE )
        else if ( bufidx > 224 )
    		{
    			// Tail modified, head updated
    			CopyBytes(B, B + FASTKDF_BUFFER_SIZE, bufidx - 224);
    		}
    }

    // Modify and copy into the output buffer

	if( (FASTKDF_BUFFER_SIZE - bufidx) < output_len)
	{
		XORBytes(output, B + bufidx, A, (FASTKDF_BUFFER_SIZE - bufidx));
		XORBytes(output + (FASTKDF_BUFFER_SIZE - bufidx), B, A + (FASTKDF_BUFFER_SIZE - bufidx), output_len - (FASTKDF_BUFFER_SIZE - bufidx));
	}
	else
      XORBytes(output, B + bufidx, A, output_len);    
}


#define SALSA_CORE(state) do { \
  state.s49e3 ^= rotate(state.s05af + state.sc16b, (uint4)( 7U, 7U, 7U, 7U)); \  
  state.s8d27 ^= rotate(state.s49e3 + state.s05af, (uint4)( 9U, 9U, 9U, 9U));  \
  state.sc16b ^= rotate(state.s8d27 + state.s49e3, (uint4)( 13U, 13U, 13U, 13U)); \ 
  state.s05af ^= rotate(state.sc16b + state.s8d27, (uint4)( 18U, 18U, 18U, 18U)); \
  \
  state.s16bc ^= rotate(state.s05af + state.s349e, (uint4)( 7U, 7U, 7U, 7U)); \  
  state.s278d ^= rotate(state.s16bc + state.s05af, (uint4)( 9U, 9U, 9U, 9U)); \ 
  state.s349e ^= rotate(state.s278d + state.s16bc, (uint4)( 13U, 13U, 13U, 13U)); \ 
  state.s05af ^= rotate(state.s349e + state.s278d, (uint4)( 18U, 18U, 18U, 18U)); \
} while(0)


uint16 salsa_small_scalar_rnd(uint16 X)
{
	uint16 st = X;

	#if SALSA_SMALL_UNROLL == 1

	for(int i = 0; i < 10; ++i)
	{
		SALSA_CORE(st);
	}

	#elif SALSA_SMALL_UNROLL == 2

	for(int i = 0; i < 5; ++i)
	{
		SALSA_CORE(st);
		SALSA_CORE(st);
	}

	#elif SALSA_SMALL_UNROLL == 3

//	for(int i = 0; i < 4; ++i)

  uint i = 4;
  while (i--) 
	{
		SALSA_CORE(st);
		if( !i ) break;
		SALSA_CORE(st);
		SALSA_CORE(st);
	} 

	#elif SALSA_SMALL_UNROLL == 4

	for(int i = 0; i < 3; ++i)
	{
		SALSA_CORE(st);
		SALSA_CORE(st);
		if(i == 2) break;
		SALSA_CORE(st);
		SALSA_CORE(st);
	}

	#else

	for(int i = 0; i < 2; ++i)
	{
		SALSA_CORE(st);
		SALSA_CORE(st);
		SALSA_CORE(st);
		SALSA_CORE(st);
		SALSA_CORE(st);
	}

	#endif

	return(X + st);
}

#define CHACHA_CORE_PARALLEL(state)	do { \
	state[0] += state[1]; state[3] = rotate(state[3] ^ state[0], (uint4)(16U, 16U, 16U, 16U)); \
	state[2] += state[3]; state[1] = rotate(state[1] ^ state[2], (uint4)(12U, 12U, 12U, 12U)); \
	state[0] += state[1]; state[3] = rotate(state[3] ^ state[0], (uint4)(8U, 8U, 8U, 8U)); \
	state[2] += state[3]; state[1] = rotate(state[1] ^ state[2], (uint4)(7U, 7U, 7U, 7U)); \
	\
	state[0] += state[1].yzwx; state[3].wxyz = rotate(state[3].wxyz ^ state[0], (uint4)(16U, 16U, 16U, 16U)); \
	state[2].zwxy += state[3].wxyz; state[1].yzwx = rotate(state[1].yzwx ^ state[2].zwxy, (uint4)(12U, 12U, 12U, 12U)); \
	state[0] += state[1].yzwx; state[3].wxyz = rotate(state[3].wxyz ^ state[0], (uint4)(8U, 8U, 8U, 8U)); \
	state[2].zwxy += state[3].wxyz; state[1].yzwx = rotate(state[1].yzwx ^ state[2].zwxy, (uint4)(7U, 7U, 7U, 7U)); \
} while(0)

uint16 chacha_small_parallel_rnd(uint16 X)
{
	uint4 st[4];

	((uint16 *)st)[0] = X;

	#if CHACHA_SMALL_UNROLL == 1

	for(int i = 0; i < 10; ++i)
	{
		CHACHA_CORE_PARALLEL(st);
	}

	#elif CHACHA_SMALL_UNROLL == 2

	for(int i = 0; i < 5; ++i)
	{
		CHACHA_CORE_PARALLEL(st);
		CHACHA_CORE_PARALLEL(st);
	}

	#elif CHACHA_SMALL_UNROLL == 3

//	for(int i = 0; i < 4; ++i)
  
  int i = 4;
  while (i--)
	{
		CHACHA_CORE_PARALLEL(st);
		if( !i ) break;
		CHACHA_CORE_PARALLEL(st);    
		CHACHA_CORE_PARALLEL(st);

	}

	#elif CHACHA_SMALL_UNROLL == 4

	for(int i = 0; i < 3; ++i)
	{
		CHACHA_CORE_PARALLEL(st);
		CHACHA_CORE_PARALLEL(st);
		if(i == 2) break;
		CHACHA_CORE_PARALLEL(st);
		CHACHA_CORE_PARALLEL(st);
	}

	#else

	for(int i = 0; i < 2; ++i)
	{
		CHACHA_CORE_PARALLEL(st);
		CHACHA_CORE_PARALLEL(st);
		CHACHA_CORE_PARALLEL(st);
		CHACHA_CORE_PARALLEL(st);
		CHACHA_CORE_PARALLEL(st);
	}

	#endif

	return(X + ((uint16 *)st)[0]);
}

void neoscrypt_blkmix(uint16 *XV, uint alg)
{
  uint16 TX;

    /* NeoScrypt flow:                   Scrypt flow:
         Xa ^= Xd;  M(Xa'); Ya = Xa";      Xa ^= Xb;  M(Xa'); Ya = Xa";
         Xb ^= Xa"; M(Xb'); Yb = Xb";      Xb ^= Xa"; M(Xb'); Yb = Xb";
         Xc ^= Xb"; M(Xc'); Yc = Xc";      Xa" = Ya;
         Xd ^= Xc"; M(Xd'); Yd = Xd";      Xb" = Yb;
         Xa" = Ya; Xb" = Yc;
         Xc" = Yb; Xd" = Yd; */
      
    if (!alg)
    {
    		XV[0] = salsa_small_scalar_rnd( XV[0] ^ XV[3] ); 
        TX =    salsa_small_scalar_rnd( XV[1] ^ XV[0] ); 
        XV[1] = salsa_small_scalar_rnd( XV[2] ^ TX ); 
        XV[3] = salsa_small_scalar_rnd( XV[3] ^ XV[1] ); 
    }
    else
    {
        XV[0] = chacha_small_parallel_rnd(XV[0] ^ XV[3] ); 
    		TX =    chacha_small_parallel_rnd(XV[1] ^ XV[0] ); 
    		XV[1] = chacha_small_parallel_rnd(XV[2] ^ TX); 
        XV[3] = chacha_small_parallel_rnd(XV[3] ^ XV[1] );      
    } 
    XV[2] = TX;      
}


void SMix(ulong16 *X, __global ulong16 *V, uint flag)
{
  uint idx;
  uint i = 0; 
    do {
       	V[i++]   = X[0];
 	      V[i++]   = X[1];           
        neoscrypt_blkmix(X, flag);
    }   while (i ^ 256);
    do {
        idx =  (((uint *)X)[48])<<1 & 0xFE;
        X[0] ^= V[idx++];
 	      X[1] ^= V[idx];    
        neoscrypt_blkmix(X, flag);    
        i-=2;
    } while (i);
}


__attribute__((reqd_work_group_size(WORKSIZE, 1, 1)))
__kernel void search(__global const uchar* restrict input, __global uint* restrict output, __global uchar *padcache, const uint target)
{
#define CONSTANT_N 128
#define CONSTANT_r 2
	// X = CONSTANT_r * 2 * BLOCK_SIZE(64); Z is a copy of X for ChaCha
	uint16 X[4], Z[4];
  bool flag = false; 
 
	/* V = CONSTANT_N * CONSTANT_r * 2 * BLOCK_SIZE */
	__global ulong16 *V = (__global ulong16 *)(padcache + ( (get_global_id(0) % MAX_GLOBAL_THREADS) << 15 ));
	uchar outbuf[32];
	uchar data[PASSWORD_LEN];

	((ulong8 *)data)[0] = ((__global const ulong8 *)input)[0];
	((ulong *)data)[8] = ((__global const ulong *)input)[8];
	((uint *)data)[18] = ((__global const uint *)input)[18];
	((uint *)data)[19] = get_global_id(0);

    // X = KDF(password, salt)
	fastkdf(data, data, PASSWORD_LEN, (uchar *)X, 256);

    // Process ChaCha 1st, Salsa 2nd and XOR them - run that through PBKDF2
//    CopyBytes128(Z, X, 2);

		((ulong16 *)Z)[0] = ((ulong16 *)X)[0];
    ((ulong16 *)Z)[1] = ((ulong16 *)X)[1];

    // X = SMix(X); X & Z are swapped, repeat.

    for( ;; ++flag)
    {
      SMix(X, V, flag);
      if (flag) break;      
//   		SwapBytes128(X, Z, 256);  
   		((ulong16 *)X)[0] ^= ((ulong16 *)Z)[0];
  		((ulong16 *)Z)[0] ^= ((ulong16 *)X)[0];
  		((ulong16 *)X)[0] ^= ((ulong16 *)Z)[0];
  		((ulong16 *)X)[1] ^= ((ulong16 *)Z)[1];
  		((ulong16 *)Z)[1] ^= ((ulong16 *)X)[1];
  		((ulong16 *)X)[1] ^= ((ulong16 *)Z)[1];  
   	}
        
	// blkxor(X, Z)
	((ulong16 *)X)[0] ^= ((ulong16 *)Z)[0];
	((ulong16 *)X)[1] ^= ((ulong16 *)Z)[1];

	// output = KDF(password, X)
	fastkdf(data, (uchar *)X, FASTKDF_BUFFER_SIZE, outbuf, 32);
	if(((uint *)outbuf)[7] <= target) output[atomic_add(output + 0xFF, 1)] = get_global_id(0);
}
