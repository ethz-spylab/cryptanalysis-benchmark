/* Full Lepton Light-I secret recovery via CC-DOOM-Prange ISD.
 * Usage: leptsolve <sigma_hex> <b_bytes_hex> [seed] [tlimit_sec]
 * Prints recovered s positions (16, any order) if wt(b+A*s)==16.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include "params.h"
#include "poly.h"

typedef uint64_t u64;
#define NN PARAM_N
#define MM PARAM_M
#define NW ((NN+63)/64)
typedef u64 bpoly[NW];

static int hx(char c){return c>='a'?c-'a'+10:(c>='A'?c-'A'+10:c-'0');}
static void ph(const char*h,unsigned char*o,int n){if(h[0]=='0'&&(h[1]=='x'||h[1]=='X'))h+=2;for(int i=0;i<n;i++)o[i]=(hx(h[2*i])<<4)|hx(h[2*i+1]);}
static inline int bget(const bpoly p,int d){return (p[d>>6]>>(d&63))&1ULL;}
static inline void bset(bpoly p,int d){p[d>>6]|=(1ULL<<(d&63));}
static int wt(const bpoly p){int w=0;for(int i=0;i<NW;i++)w+=__builtin_popcountll(p[i]);return w;}
static void a_from_seed(bpoly o,const unsigned char*s){poly aw;poly_getrandom(aw,(unsigned char*)s,0);memset(o,0,sizeof(bpoly));for(int d=0;d<NN;d++)if((aw[d>>5]>>(31-(d&31)))&1u)bset(o,d);}
static void b_from_bytes(bpoly o,const unsigned char*bb){poly bw;memset(bw,0,sizeof(bw));int j=0,k=(POLY_BYTES>>2);for(int i=0;i<k;i++){bw[i]=((uint32_t)bb[j]<<24)|((uint32_t)bb[j+1]<<16)|((uint32_t)bb[j+2]<<8)|bb[j+3];j+=4;}int r=POLY_BYTES&3;if(r){bw[POLY_WORDS-1]=0;for(int kk=0;kk<r;kk++)bw[POLY_WORDS-1]|=((uint32_t)bb[j++])<<((3-kk)*8);}memset(o,0,sizeof(bpoly));for(int d=0;d<NN;d++)if((bw[d>>5]>>(31-(d&31)))&1u)bset(o,d);}
static void mulX(bpoly p){int c=bget(p,NN-1);u64 pr=0;for(int i=0;i<NW;i++){u64 nw=(p[i]<<1)|pr;pr=p[i]>>63;p[i]=nw;}p[NN>>6]&=~(1ULL<<(NN&63));if(c){p[0]^=1ULL;p[MM>>6]^=(1ULL<<(MM&63));}}
static void mulXinv(bpoly p){int c=bget(p,0);u64 nx=0;for(int i=NW-1;i>=0;i--){u64 nw=(p[i]>>1)|(nx<<63);nx=p[i]&1ULL;p[i]=nw;}if(c){p[(NN-1)>>6]^=(1ULL<<((NN-1)&63));p[(MM-1)>>6]^=(1ULL<<((MM-1)&63));}}

/* ---- engine (validated) ---- */
typedef struct{int R,Ncode,NS,SW,synw,stride;u64*M;int*pivcol;char*ispiv;int*nonpiv,nnp,*npidx;}eng;
static inline u64* erow(eng*e,int r){return e->M+(size_t)r*e->stride;}
static inline int cbit(eng*e,int r,int c){return (erow(e,r)[c>>6]>>(c&63))&1ULL;}
static inline int sbit(eng*e,int r,int i){return (erow(e,r)[e->SW+(i>>6)]>>(i&63))&1ULL;}
static inline void scode(eng*e,int r,int c){erow(e,r)[c>>6]|=(1ULL<<(c&63));}
static inline void ssyn(eng*e,int r,int i){erow(e,r)[e->SW+(i>>6)]|=(1ULL<<(i&63));}
static eng*eng_new(int R,int Nc,int NS){eng*e=calloc(1,sizeof(eng));e->R=R;e->Ncode=Nc;e->NS=NS;int cw=(Nc+63)/64;e->SW=cw;e->synw=(NS+63)/64;e->stride=cw+e->synw;e->M=calloc((size_t)R*e->stride,8);e->pivcol=malloc(R*4);e->ispiv=malloc(Nc);e->nonpiv=malloc(Nc*4);e->npidx=malloc(Nc*4);return e;}
static int init_reduce(eng*e){int pr=0;for(int c=0;c<e->Ncode&&pr<e->R;c++){int pv=-1;for(int r=pr;r<e->R;r++)if(cbit(e,r,c)){pv=r;break;}if(pv<0)continue;if(pv!=pr){u64*a=erow(e,pr),*b=erow(e,pv);for(int w=0;w<e->stride;w++){u64 t=a[w];a[w]=b[w];b[w]=t;}}u64*p=erow(e,pr);for(int r=0;r<e->R;r++){if(r==pr)continue;if(cbit(e,r,c)){u64*rr=erow(e,r);for(int w=0;w<e->stride;w++)rr[w]^=p[w];}}e->pivcol[pr]=c;pr++;}if(pr!=e->R){fprintf(stderr,"rank %d<%d\n",pr,e->R);return -1;}for(int c=0;c<e->Ncode;c++)e->ispiv[c]=0;for(int r=0;r<e->R;r++)e->ispiv[e->pivcol[r]]=1;e->nnp=0;for(int c=0;c<e->Ncode;c++){if(!e->ispiv[c]){e->npidx[c]=e->nnp;e->nonpiv[e->nnp++]=c;}else e->npidx[c]=-1;}return 0;}
static int cc_step(eng*e){int p=rand()%e->R;u64*pv=erow(e,p);int mu=-1;for(int t=0;t<12;t++){int c=e->nonpiv[rand()%e->nnp];if(cbit(e,p,c)){mu=c;break;}}if(mu<0){for(int c=0;c<e->Ncode;c++)if(!e->ispiv[c]&&cbit(e,p,c)){mu=c;break;}if(mu<0)return 0;}int lam=e->pivcol[p];for(int r=0;r<e->R;r++){if(r==p)continue;if(cbit(e,r,mu)){u64*rr=erow(e,r);for(int w=0;w<e->stride;w++)rr[w]^=pv[w];}}e->pivcol[p]=mu;e->ispiv[mu]=1;e->ispiv[lam]=0;int im=e->npidx[mu];e->nonpiv[im]=lam;e->npidx[lam]=im;e->npidx[mu]=-1;return 1;}
#define WIN_L 20
#define WIN_K 2
/* p=0 DOOM check: rotations whose reduced syndrome is all-zero on window rows -> full weight<=thresh */
static int check_sol(eng*e,int thresh,int*eo,int*en){static u64 orv[8192];for(int win=0;win<WIN_K;win++){for(int w=0;w<e->synw;w++)orv[w]=0;for(int rr=0;rr<WIN_L;rr++){u64*S=erow(e,win*WIN_L+rr)+e->SW;for(int w=0;w<e->synw;w++)orv[w]|=S[w];}for(int w=0;w<e->synw;w++){u64 z=~orv[w];while(z){int b=__builtin_ctzll(z);z&=z-1;int i=w*64+b;if(i>=e->NS)continue;int c=0;for(int r=0;r<e->R;r++){c+=sbit(e,r,i);if(c>thresh)break;}if(c<=thresh){int cnt=0;for(int r=0;r<e->R;r++)if(sbit(e,r,i))eo[cnt++]=e->pivcol[r];*en=cnt;return i;}}}}return -1;}

/* ISD used here is quasi-cyclic DOOM-Prange (check_sol). Reliably in-budget only for
 * the scaled-down variants (reduced PARAM_K); the full-strength Light-I set
 * (PARAM_K=16) is left as an unsolved challenge in the base task. */

#include "lepton_kem.h"
int main(int argc,char**argv){
  /* argv[1]=pk_hex (CCA_PK_BYTES), argv[2]=ct_hex (CCA_CT_BYTES), argv[3]=seed, argv[4]=tlim */
  static unsigned char pkbytes[CCA_PK_BYTES], ctbytes[CCA_CT_BYTES];
  ph(argv[1],pkbytes,CCA_PK_BYTES); ph(argv[2],ctbytes,CCA_CT_BYTES);
  int seed=argc>3?atoi(argv[3]):1; double tlim=argc>4?atof(argv[4]):600.0;
  srand(seed);
  unsigned char sigma[SEED_BYTES],bb[POLY_BYTES];
  memcpy(sigma,pkbytes,SEED_BYTES);
  memcpy(bb,pkbytes+SEED_BYTES,POLY_BYTES);
  bpoly a,b; a_from_seed(a,sigma); b_from_bytes(b,bb);
  int R=NN, Nc=2*NN, NS=NN;
  eng*e=eng_new(R,Nc,NS);
  /* A-block: col j = a*X^j */
  bpoly cur; memcpy(cur,a,sizeof(bpoly));
  for(int j=0;j<NN;j++){ for(int wi=0;wi<NW;wi++){u64 x=cur[wi];while(x){int b2=__builtin_ctzll(x);x&=x-1;scode(e,wi*64+b2,j);}} mulX(cur);}
  /* I-block */
  for(int i=0;i<NN;i++) scode(e,i,NN+i);
  /* syndrome rotations: col i = X^i * b */
  memcpy(cur,b,sizeof(bpoly));
  for(int i=0;i<NN;i++){ for(int wi=0;wi<NW;wi++){u64 x=cur[wi];while(x){int b2=__builtin_ctzll(x);x&=x-1;ssyn(e,wi*64+b2,i);}} mulX(cur);}
  fprintf(stderr,"[%d] matrix built. reducing...\n",seed);
  if(init_reduce(e)){fprintf(stderr,"init_reduce failed\n");return 2;}
  const int THRESH=2*PARAM_K+16;  /* covers weight-2K solution plus wrap-splits (K=16 -> 48) */
  int eo[256],en; clock_t t0=clock(); long steps=0;
  for(;;){
    int found=check_sol(e,THRESH,eo,&en);
    if(found>=0){
      double el=(double)(clock()-t0)/CLOCKS_PER_SEC;
      /* A-block err cols = supp(X^found * s); unshift by 'found' to get s */
      bpoly P; memset(P,0,sizeof(P));
      for(int i=0;i<en;i++) if(eo[i]<NN) bset(P,eo[i]);
      bpoly Ps; memcpy(Ps,P,sizeof(bpoly));
      for(int t=0;t<found;t++) mulXinv(Ps);
      /* verify wt(b + A*Ps)==16 and wt(Ps)==16 */
      bpoly acc; memset(acc,0,sizeof(acc)); memcpy(cur,a,sizeof(bpoly));
      int maxp=-1; for(int d=0;d<NN;d++) if(bget(Ps,d)) maxp=d;
      for(int d=0;d<=maxp;d++){ if(bget(Ps,d)) for(int wi=0;wi<NW;wi++)acc[wi]^=cur[wi]; mulX(cur);}
      bpoly ee; memcpy(ee,b,sizeof(bpoly)); for(int wi=0;wi<NW;wi++)ee[wi]^=acc[wi];
      int ew=wt(ee), sw=wt(Ps);
      if(ew==PARAM_K && sw==PARAM_K){
        fprintf(stderr,"[%d] FOUND rot=%d synwt=%d steps=%ld %.1fs VERIFY ok; s:",seed,found,en,steps,el);
        for(int d=0;d<NN;d++) if(bget(Ps,d)) fprintf(stderr," %d",d);
        fprintf(stderr,"\n");
        /* build sk = pk || s-positions (any order), then decapsulate ct -> ss */
        static unsigned char sk[CCA_SK_BYTES], ss[SEED_BYTES];
        memcpy(sk,pkbytes,CCA_PK_BYTES);
        int idx=0;
        for(int d=0;d<NN && idx<PARAM_K;d++) if(bget(Ps,d)){ sk[CCA_PK_BYTES+2*idx]=(d>>8)&0xff; sk[CCA_PK_BYTES+2*idx+1]=d&0xff; idx++; }
        int dr=lepton_kem_dec(ss,sk,ctbytes);
        fprintf(stderr,"[%d] lepton_kem_dec ret=%d\n",seed,dr);
        printf("shared_secret: 0x");
        for(int i=0;i<SEED_BYTES;i++) printf("%02x",ss[i]);
        printf("\n");
        return (dr==0)?0:5;
      }
      /* false positive (a low-weight solution not corresponding to weight-16 s): keep going */
    }
    cc_step(e); steps++;
    if((steps&8191)==0){
      double el=(double)(clock()-t0)/CLOCKS_PER_SEC;
      if(steps%262144==0) fprintf(stderr,"[%d] steps=%ld %.1fs %.0f st/s\n",seed,steps,el,steps/el);
      if(el>tlim){fprintf(stderr,"[%d] TIMEOUT steps=%ld %.1fs\n",seed,steps,el);return 1;}
    }
  }
}
