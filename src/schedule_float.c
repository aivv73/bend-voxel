#include <ctype.h>
#include <float.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static double (*volatile schedule_float_power)(double,double)=pow;

static double schedule_float_round(double value) {
  volatile double rounded=value;
  return rounded;
}

static double schedule_float_f32(double value) {
  volatile float rounded=(float)value;
  return rounded;
}

static double schedule_float_sum3(double a,double b,double c) {
  double values[2]={b,c},high=schedule_float_round(0.0+a),low=0.0;
  for(size_t i=0;i<2;i++) {
    double value=values[i],next=schedule_float_round(high+value);
    double error=fabs(high)>=fabs(value)?schedule_float_round(schedule_float_round(high-next)+value):
      schedule_float_round(schedule_float_round(value-next)+high);
    low=schedule_float_round(low+error);
    high=next;
  }
  return low?schedule_float_round(high+low):high;
}

// Python's compensated hypot rounds differently from the platform hypot.
static double schedule_float_hypot(double a,double b) {
  double values[2]={fabs(a),fabs(b)},maximum=fmax(values[0],values[1]);
  if(maximum==0.0) return maximum;
  int exponent;
  frexp(maximum,&exponent);
  if(exponent < -1023)
    return schedule_float_round(DBL_MIN*schedule_float_hypot(a/DBL_MIN,b/DBL_MIN));
  double scale=ldexp(1.0,-exponent),total=1.0,product_error=0.0,sum_error=0.0;
  for(size_t i=0;i<2;i++) {
    double value=schedule_float_round(values[i]*scale);
    double square=schedule_float_round(value*value);
    double next=schedule_float_round(total+square);
    product_error=schedule_float_round(product_error+fma(value,value,-square));
    sum_error=schedule_float_round(sum_error+schedule_float_round(schedule_float_round(total-next)+square));
    total=next;
  }
  double result=sqrt(schedule_float_round(schedule_float_round(total-1.0)+schedule_float_round(product_error+sum_error)));
  double square=schedule_float_round(-result*result),next=schedule_float_round(total+square);
  product_error=schedule_float_round(product_error+fma(-result,result,-square));
  sum_error=schedule_float_round(sum_error+schedule_float_round(schedule_float_round(total-next)+square));
  double remainder=schedule_float_round(schedule_float_round(next-1.0)+schedule_float_round(product_error+sum_error));
  result=schedule_float_round(result+schedule_float_round(remainder/schedule_float_round(2.0*result)));
  return schedule_float_round(result/scale);
}

// Format 2 retains IEEE positive overflow for benchmark statistics only.
static double schedule_float_eval(char* code,int benchmark) {
  size_t capacity=strlen(code)+1,depth=0;
  double* stack=malloc(capacity*sizeof(double));
  if(!stack) err_fail("schedule numeric allocation failed");
  char* cursor=code;
  while(*cursor) {
    while(isspace((unsigned char)*cursor)) cursor++;
    if(!*cursor) break;
    char* token=cursor;
    while(*cursor && !isspace((unsigned char)*cursor)) cursor++;
    if(*cursor) *cursor++=0;
    char* end;
    double literal=strtod(token,&end);
    if(end!=token && !*end) {
      if(!isfinite(literal) && !(benchmark && literal==INFINITY)) err_fail("nonfinite schedule numeric literal");
      stack[depth++]=literal;
      continue;
    }
    size_t arity;
    if(!strcmp(token,"sum3")) arity=3;
    else if(!strcmp(token,"add") || !strcmp(token,"sub") || !strcmp(token,"mul") ||
            !strcmp(token,"div") || !strcmp(token,"hypot") || !strcmp(token,"atan2") || !strcmp(token,"max")) arity=2;
    else if(!strcmp(token,"pow2") || !strcmp(token,"sqrt") || !strcmp(token,"round32") ||
            !strcmp(token,"sin32") || !strcmp(token,"cos32") || !strcmp(token,"sqrt32")) arity=1;
    else err_fail("invalid schedule numeric operation");
    if(depth<arity) err_fail("invalid schedule numeric expression");
    double a=stack[depth-arity],b=arity>1?stack[depth-arity+1]:0.0,value;
    if(!strcmp(token,"add")) value=schedule_float_round(a+b);
    else if(!strcmp(token,"sub")) value=schedule_float_round(a-b);
    else if(!strcmp(token,"mul")) value=schedule_float_round(a*b);
    else if(!strcmp(token,"pow2")) value=schedule_float_power(a,2.0);
    else if(!strcmp(token,"div")) value=schedule_float_round(a/b);
    else if(!strcmp(token,"hypot")) value=schedule_float_hypot(a,b);
    else if(!strcmp(token,"atan2")) value=atan2(a,b);
    else if(!strcmp(token,"max")) value=a>=b?a:b;
    else if(!strcmp(token,"sqrt")) value=sqrt(a);
    else if(!strcmp(token,"round32")) value=schedule_float_f32(a);
    else if(!strcmp(token,"sin32")) value=sinf((float)a);
    else if(!strcmp(token,"cos32")) value=cosf((float)a);
    else if(!strcmp(token,"sqrt32")) value=sqrtf((float)a);
    else value=schedule_float_sum3(a,b,stack[depth-1]);
    if(!isfinite(value) && !(benchmark && value==INFINITY)) err_fail("nonfinite schedule numeric result");
    depth-=arity;
    stack[depth++]=value;
  }
  if(depth!=1) err_fail("incomplete schedule numeric expression");
  double result=stack[0];
  free(stack);
  return result;
}

Term host_run(Env e,Term* f,IoWork* work) {
  size_t length;
  char* code=io_cstr(e,f[0],&length);
  if((u32)f[1]==3) {
    char* end;
    double value=strtod(code,&end);
    int valid=length<=1048576 && !memchr(code,0,length) && end!=code && !*end && isfinite(value);
    free(code);
    if(!valid) return io_str(e,"invalid",7);
    char result[64];
    int written=snprintf(result,sizeof result,"%a",value);
    if(written<0 || written>=(int)sizeof result) return io_str(e,"invalid",7);
    return io_str(e,result,(size_t)written);
  }
  if(length>1048576 || memchr(code,0,length)) err_fail("invalid schedule numeric input");
  double value=schedule_float_eval(code,(u32)f[1]==2);
  free(code);
  char result[64];
  int written;
  if((u32)f[1]==0 || (u32)f[1]==2) written=snprintf(result,sizeof result,"%a",value);
  else if((u32)f[1]==1) {
    float rounded=(float)value;
    uint32_t word;
    if(!isfinite(rounded)) err_fail("nonfinite schedule binary32 result");
    memcpy(&word,&rounded,sizeof word);
    written=snprintf(result,sizeof result,"\"0x%08x\"",word);
  } else err_fail("invalid schedule numeric format");
  if(written<0 || written>=(int)sizeof result) err_fail("schedule numeric output overflow");
  return io_str(e,result,(size_t)written);
}

static void __attribute__((constructor)) host_use(void) {
  io_eff(CID(host),host_run,0);
}
