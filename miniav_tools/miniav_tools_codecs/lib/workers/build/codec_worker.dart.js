(function dartProgram(){function copyProperties(a,b){var s=Object.keys(a)
for(var r=0;r<s.length;r++){var q=s[r]
b[q]=a[q]}}function mixinPropertiesHard(a,b){var s=Object.keys(a)
for(var r=0;r<s.length;r++){var q=s[r]
if(!b.hasOwnProperty(q)){b[q]=a[q]}}}function mixinPropertiesEasy(a,b){Object.assign(b,a)}var z=function(){var s=function(){}
s.prototype={p:{}}
var r=new s()
if(!(Object.getPrototypeOf(r)&&Object.getPrototypeOf(r).p===s.prototype.p))return false
try{if(typeof navigator!="undefined"&&typeof navigator.userAgent=="string"&&navigator.userAgent.indexOf("Chrome/")>=0)return true
if(typeof version=="function"&&version.length==0){var q=version()
if(/^\d+\.\d+\.\d+\.\d+$/.test(q))return true}}catch(p){}return false}()
function inherit(a,b){a.prototype.constructor=a
a.prototype["$i"+a.name]=a
if(b!=null){if(z){Object.setPrototypeOf(a.prototype,b.prototype)
return}var s=Object.create(b.prototype)
copyProperties(a.prototype,s)
a.prototype=s}}function inheritMany(a,b){for(var s=0;s<b.length;s++){inherit(b[s],a)}}function mixinEasy(a,b){mixinPropertiesEasy(b.prototype,a.prototype)
a.prototype.constructor=a}function mixinHard(a,b){mixinPropertiesHard(b.prototype,a.prototype)
a.prototype.constructor=a}function lazy(a,b,c,d){var s=a
a[b]=s
a[c]=function(){if(a[b]===s){a[b]=d()}a[c]=function(){return this[b]}
return a[b]}}function lazyFinal(a,b,c,d){var s=a
a[b]=s
a[c]=function(){if(a[b]===s){var r=d()
if(a[b]!==s){A.jr(b)}a[b]=r}var q=a[b]
a[c]=function(){return q}
return q}}function makeConstList(a,b){if(b!=null)A.z(a,b)
a.$flags=7
return a}function convertToFastObject(a){function t(){}t.prototype=a
new t()
return a}function convertAllToFastObject(a){for(var s=0;s<a.length;++s){convertToFastObject(a[s])}}var y=0
function instanceTearOffGetter(a,b){var s=null
return a?function(c){if(s===null)s=A.eZ(b)
return new s(c,this)}:function(){if(s===null)s=A.eZ(b)
return new s(this,null)}}function staticTearOffGetter(a){var s=null
return function(){if(s===null)s=A.eZ(a).prototype
return s}}var x=0
function tearOffParameters(a,b,c,d,e,f,g,h,i,j){if(typeof h=="number"){h+=x}return{co:a,iS:b,iI:c,rC:d,dV:e,cs:f,fs:g,fT:h,aI:i||0,nDA:j}}function installStaticTearOff(a,b,c,d,e,f,g,h){var s=tearOffParameters(a,true,false,c,d,e,f,g,h,false)
var r=staticTearOffGetter(s)
a[b]=r}function installInstanceTearOff(a,b,c,d,e,f,g,h,i,j){c=!!c
var s=tearOffParameters(a,false,c,d,e,f,g,h,i,!!j)
var r=instanceTearOffGetter(c,s)
a[b]=r}function setOrUpdateInterceptorsByTag(a){var s=v.interceptorsByTag
if(!s){v.interceptorsByTag=a
return}copyProperties(a,s)}function setOrUpdateLeafTags(a){var s=v.leafTags
if(!s){v.leafTags=a
return}copyProperties(a,s)}function updateTypes(a){var s=v.types
var r=s.length
s.push.apply(s,a)
return r}function updateHolder(a,b){copyProperties(b,a)
return a}var hunkHelpers=function(){var s=function(a,b,c,d,e){return function(f,g,h,i){return installInstanceTearOff(f,g,a,b,c,d,[h],i,e,false)}},r=function(a,b,c,d){return function(e,f,g,h){return installStaticTearOff(e,f,a,b,c,[g],h,d)}}
return{inherit:inherit,inheritMany:inheritMany,mixin:mixinEasy,mixinHard:mixinHard,installStaticTearOff:installStaticTearOff,installInstanceTearOff:installInstanceTearOff,_instance_0u:s(0,0,null,["$0"],0),_instance_1u:s(0,1,null,["$1"],0),_instance_2u:s(0,2,null,["$2"],0),_instance_0i:s(1,0,null,["$0"],0),_instance_1i:s(1,1,null,["$1"],0),_instance_2i:s(1,2,null,["$2"],0),_static_0:r(0,null,["$0"],0),_static_1:r(1,null,["$1"],0),_static_2:r(2,null,["$2"],0),makeConstList:makeConstList,lazy:lazy,lazyFinal:lazyFinal,updateHolder:updateHolder,convertToFastObject:convertToFastObject,updateTypes:updateTypes,setOrUpdateInterceptorsByTag:setOrUpdateInterceptorsByTag,setOrUpdateLeafTags:setOrUpdateLeafTags}}()
function initializeDeferredHunk(a){x=v.types.length
a(hunkHelpers,v,w,$)}var J={
f3(a,b,c,d){return{i:a,p:b,e:c,x:d}},
eo(a){var s,r,q,p,o,n="_$dart_js",m=a[v.dispatchPropertyName]
if(m==null)if($.f1==null){A.jg()
m=a[v.dispatchPropertyName]}if(m!=null){s=m.p
if(!1===s)return m.i
if(!0===s)return a
r=Object.getPrototypeOf(a)
if(s===r)return m.i
if(m.e===r)throw A.b(A.fy("Return interceptor for "+A.j(s(a,m))))}q=a.constructor
if(q==null)p=null
else{o=$.dW
if(o==null)o=$.dW=A.en(n)
p=q[o]}if(p!=null)return p
p=A.jk(a)
if(p!=null)return p
if(typeof a=="function")return B.T
s=Object.getPrototypeOf(a)
if(s==null)return B.x
if(s===Object.prototype)return B.x
if(typeof q=="function"){o=$.dW
if(o==null)o=$.dW=A.en(n)
Object.defineProperty(q,o,{value:B.k,enumerable:false,writable:true,configurable:true})
return B.k}return B.k},
ac(a){if(typeof a=="number"){if(Math.floor(a)==a)return J.bf.prototype
return J.cl.prototype}if(typeof a=="string")return J.aH.prototype
if(a==null)return J.bg.prototype
if(typeof a=="boolean")return J.ck.prototype
if(Array.isArray(a))return J.p.prototype
if(typeof a!="object"){if(typeof a=="function")return J.a7.prototype
if(typeof a=="symbol")return J.aJ.prototype
if(typeof a=="bigint")return J.aI.prototype
return a}if(a instanceof A.c)return a
return J.eo(a)},
h4(a){if(typeof a=="string")return J.aH.prototype
if(a==null)return a
if(Array.isArray(a))return J.p.prototype
if(typeof a!="object"){if(typeof a=="function")return J.a7.prototype
if(typeof a=="symbol")return J.aJ.prototype
if(typeof a=="bigint")return J.aI.prototype
return a}if(a instanceof A.c)return a
return J.eo(a)},
h5(a){if(a==null)return a
if(Array.isArray(a))return J.p.prototype
if(typeof a!="object"){if(typeof a=="function")return J.a7.prototype
if(typeof a=="symbol")return J.aJ.prototype
if(typeof a=="bigint")return J.aI.prototype
return a}if(a instanceof A.c)return a
return J.eo(a)},
jd(a){if(a==null)return a
if(typeof a!="object"){if(typeof a=="function")return J.a7.prototype
if(typeof a=="symbol")return J.aJ.prototype
if(typeof a=="bigint")return J.aI.prototype
return a}if(a instanceof A.c)return a
return J.eo(a)},
eA(a,b){if(a==null)return b==null
if(typeof a!="object")return b!=null&&a===b
return J.ac(a).D(a,b)},
ht(a,b,c){return J.jd(a).b0(a,b,c)},
P(a){return J.ac(a).gl(a)},
hu(a){return J.h5(a).gb6(a)},
eB(a){return J.h5(a).gu(a)},
f7(a){return J.h4(a).gp(a)},
b6(a){return J.ac(a).gk(a)},
aD(a){return J.ac(a).i(a)},
ci:function ci(){},
ck:function ck(){},
bg:function bg(){},
bi:function bi(){},
ag:function ag(){},
cq:function cq(){},
bB:function bB(){},
a7:function a7(){},
aI:function aI(){},
aJ:function aJ(){},
p:function p(a){this.$ti=a},
cj:function cj(){},
d4:function d4(a){this.$ti=a},
b7:function b7(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
bh:function bh(){},
bf:function bf(){},
cl:function cl(){},
aH:function aH(){}},A={eD:function eD(){},
M(a,b){a=a+b&536870911
a=a+((a&524287)<<10)&536870911
return a^a>>>6},
di(a){a=a+((a&67108863)<<3)&536870911
a^=a>>>11
return a+((a&16383)<<15)&536870911},
eY(a,b,c){return a},
f2(a){var s,r
for(s=$.O.length,r=0;r<s;++r)if(a===$.O[r])return!0
return!1},
hH(a,b,c,d){if(t.x.b(a))return new A.bc(a,b,c.h("@<0>").t(d).h("bc<1,2>"))
return new A.as(a,b,c.h("@<0>").t(d).h("as<1,2>"))},
aK:function aK(a){this.a=a},
eu:function eu(){},
de:function de(){},
i:function i(){},
bn:function bn(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
as:function as(a,b,c){this.a=a
this.b=b
this.$ti=c},
bc:function bc(a,b,c){this.a=a
this.b=b
this.$ti=c},
bp:function bp(a,b,c){var _=this
_.a=null
_.b=a
_.c=b
_.$ti=c},
E:function E(){},
he(a){var s=A.hd(a)
if(s!=null)return s
return"minified:"+a},
jQ(a,b){var s
if(b!=null){s=b.x
if(s!=null)return s}return t.aU.b(a)},
j(a){var s
if(typeof a=="string")return a
if(typeof a=="number"){if(a!==0)return""+a}else if(!0===a)return"true"
else if(!1===a)return"false"
else if(a==null)return"null"
s=J.aD(a)
return s},
bu(a){var s,r=$.fo
if(r==null)r=$.fo=Symbol("identityHashCode")
s=a[r]
if(s==null){s=Math.random()*0x3fffffff|0
a[r]=s}return s},
cr(a){var s,r,q,p
if(a instanceof A.c)return A.C(A.b4(a),null)
s=J.ac(a)
if(s===B.S||s===B.U||t.bI.b(a)){r=B.t(a)
if(r!=="Object"&&r!=="")return r
q=a.constructor
if(typeof q=="function"){p=q.name
if(typeof p=="string"&&p!=="Object"&&p!=="")return p}}return A.C(A.b4(a),null)},
fp(a){var s,r,q
if(a==null||typeof a=="number"||A.cQ(a))return J.aD(a)
if(typeof a=="string")return JSON.stringify(a)
if(a instanceof A.af)return a.i(0)
if(a instanceof A.az)return a.b_(!0)
s=$.hr()
for(r=0;r<1;++r){q=s[r].c0(a)
if(q!=null)return q}return"Instance of '"+A.cr(a)+"'"},
y(a){var s
if(a<=65535)return String.fromCharCode(a)
if(a<=1114111){s=a-65536
return String.fromCharCode((B.c.aW(s,10)|55296)>>>0,s&1023|56320)}throw A.b(A.bw(a,0,1114111,null,null))},
hJ(a){var s=a.$thrownJsError
if(s==null)return null
return A.I(s)},
fq(a,b){var s
if(a.$thrownJsError==null){s=new Error()
A.w(a,s)
a.$thrownJsError=s
s.stack=b.i(0)}},
h(a,b){if(a==null)J.f7(a)
throw A.b(A.h3(a,b))},
h3(a,b){var s,r="index"
if(!A.eT(b))return new A.a3(!0,b,r,null)
s=A.G(J.f7(a))
if(b<0||b>=s)return A.fh(b,s,a,r)
return A.fr(b,r)},
j8(a,b,c){if(a>c)return A.bw(a,0,c,"start",null)
if(b!=null)if(b<a||b>c)return A.bw(b,a,c,"end",null)
return new A.a3(!0,b,"end",null)},
b(a){return A.w(a,new Error())},
w(a,b){var s
if(a==null)a=new A.a9()
b.dartException=a
s=A.js
if("defineProperty" in Object){Object.defineProperty(b,"message",{get:s})
b.name=""}else b.toString=s
return b},
js(){return J.aD(this.dartException)},
ad(a,b){throw A.w(a,b==null?new Error():b)},
ae(a,b,c){var s
if(b==null)b=0
if(c==null)c=0
s=Error()
A.ad(A.iq(a,b,c),s)},
iq(a,b,c){var s,r,q,p,o,n,m,l,k
if(typeof b=="string")s=b
else{r="[]=;add;removeWhere;retainWhere;removeRange;setRange;setInt8;setInt16;setInt32;setUint8;setUint16;setUint32;setFloat32;setFloat64".split(";")
q=r.length
p=b
if(p>q){c=p/q|0
p%=q}s=r[p]}o=typeof c=="string"?c:"modify;remove from;add to".split(";")[c]
n=t.j.b(a)?"list":"ByteData"
m=a.$flags|0
l="a "
if((m&4)!==0)k="constant "
else if((m&2)!==0){k="unmodifiable "
l="an "}else k=(m&1)!==0?"fixed-length ":""
return new A.bC("'"+s+"': Cannot "+o+" "+l+k+n)},
an(a){throw A.b(A.cc(a))},
aa(a){var s,r,q,p,o,n
a=A.hc(a.replace(String({}),"$receiver$"))
s=a.match(/\\\$[a-zA-Z]+\\\$/g)
if(s==null)s=A.z([],t.s)
r=s.indexOf("\\$arguments\\$")
q=s.indexOf("\\$argumentsExpr\\$")
p=s.indexOf("\\$expr\\$")
o=s.indexOf("\\$method\\$")
n=s.indexOf("\\$receiver\\$")
return new A.dj(a.replace(new RegExp("\\\\\\$arguments\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$argumentsExpr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$expr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$method\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$receiver\\\\\\$","g"),"((?:x|[^x])*)"),r,q,p,o,n)},
dk(a){return function($expr$){var $argumentsExpr$="$arguments$"
try{$expr$.$method$($argumentsExpr$)}catch(s){return s.message}}(a)},
fx(a){return function($expr$){try{$expr$.$method$}catch(s){return s.message}}(a)},
eE(a,b){var s=b==null,r=s?null:b.method
return new A.cm(a,r,s?null:b.receiver)},
D(a){var s
if(a==null)return new A.dd(a)
if(a instanceof A.be){s=a.a
return A.am(a,s==null?A.a6(s):s)}if(typeof a!=="object")return a
if("dartException" in a)return A.am(a,a.dartException)
return A.iY(a)},
am(a,b){if(t.C.b(b))if(b.$thrownJsError==null)b.$thrownJsError=a
return b},
iY(a){var s,r,q,p,o,n,m,l,k,j,i,h,g
if(!("message" in a))return a
s=a.message
if("number" in a&&typeof a.number=="number"){r=a.number
q=r&65535
if((B.c.aW(r,16)&8191)===10)switch(q){case 438:return A.am(a,A.eE(A.j(s)+" (Error "+q+")",null))
case 445:case 5007:A.j(s)
return A.am(a,new A.bt())}}if(a instanceof TypeError){p=$.hg()
o=$.hh()
n=$.hi()
m=$.hj()
l=$.hm()
k=$.hn()
j=$.hl()
$.hk()
i=$.hp()
h=$.ho()
g=p.A(s)
if(g!=null)return A.am(a,A.eE(A.a1(s),g))
else{g=o.A(s)
if(g!=null){g.method="call"
return A.am(a,A.eE(A.a1(s),g))}else if(n.A(s)!=null||m.A(s)!=null||l.A(s)!=null||k.A(s)!=null||j.A(s)!=null||m.A(s)!=null||i.A(s)!=null||h.A(s)!=null){A.a1(s)
return A.am(a,new A.bt())}}return A.am(a,new A.cz(typeof s=="string"?s:""))}if(a instanceof RangeError){if(typeof s=="string"&&s.indexOf("call stack")!==-1)return new A.by()
s=function(b){try{return String(b)}catch(f){}return null}(a)
return A.am(a,new A.a3(!1,null,null,typeof s=="string"?s.replace(/^RangeError:\s*/,""):s))}if(typeof InternalError=="function"&&a instanceof InternalError)if(typeof s=="string"&&s==="too much recursion")return new A.by()
return a},
I(a){var s
if(a instanceof A.be)return a.b
if(a==null)return new A.bO(a)
s=a.$cachedTrace
if(s!=null)return s
s=new A.bO(a)
if(typeof a==="object")a.$cachedTrace=s
return s},
h8(a){if(a==null)return J.P(a)
if(typeof a=="object")return A.bu(a)
return J.P(a)},
jc(a,b){var s,r,q,p=a.length
for(s=0;s<p;s=q){r=s+1
q=r+1
b.E(0,a[s],a[r])}return b},
iz(a,b,c,d,e,f){t.Z.a(a)
switch(A.G(b)){case 0:return a.$0()
case 1:return a.$1(c)
case 2:return a.$2(c,d)
case 3:return a.$3(c,d,e)
case 4:return a.$4(c,d,e,f)}throw A.b(new A.dG("Unsupported number of arguments for wrapped closure"))},
c2(a,b){var s=a.$identity
if(!!s)return s
s=A.j5(a,b)
a.$identity=s
return s},
j5(a,b){var s
switch(b){case 0:s=a.$0
break
case 1:s=a.$1
break
case 2:s=a.$2
break
case 3:s=a.$3
break
case 4:s=a.$4
break
default:s=null}if(s!=null)return s.bind(a)
return function(c,d,e){return function(f,g,h,i){return e(c,d,f,g,h,i)}}(a,b,A.iz)},
hB(a2){var s,r,q,p,o,n,m,l,k,j,i=a2.co,h=a2.iS,g=a2.iI,f=a2.nDA,e=a2.aI,d=a2.fs,c=a2.cs,b=d[0],a=c[0],a0=i[b],a1=a2.fT
a1.toString
s=h?Object.create(new A.cv().constructor.prototype):Object.create(new A.aF(null,null).constructor.prototype)
s.$initialize=s.constructor
r=h?function static_tear_off(){this.$initialize()}:function tear_off(a3,a4){this.$initialize(a3,a4)}
s.constructor=r
r.prototype=s
s.$_name=b
s.$_target=a0
q=!h
if(q)p=A.fd(b,a0,g,f)
else{s.$static_name=b
p=a0}s.$S=A.hx(a1,h,g)
s[a]=p
for(o=p,n=1;n<d.length;++n){m=d[n]
if(typeof m=="string"){l=i[m]
k=m
m=l}else k=""
j=c[n]
if(j!=null){if(q)m=A.fd(k,m,g,f)
s[j]=m}if(n===e)o=m}s.$C=o
s.$R=a2.rC
s.$D=a2.dV
return r},
hx(a,b,c){if(typeof a=="number")return a
if(typeof a=="string"){if(b)throw A.b("Cannot compute signature for static tearoff.")
return function(d,e){return function(){return e(this,d)}}(a,A.hv)}throw A.b("Error in functionType of tearoff")},
hy(a,b,c,d){var s=A.fb
switch(b?-1:a){case 0:return function(e,f){return function(){return f(this)[e]()}}(c,s)
case 1:return function(e,f){return function(g){return f(this)[e](g)}}(c,s)
case 2:return function(e,f){return function(g,h){return f(this)[e](g,h)}}(c,s)
case 3:return function(e,f){return function(g,h,i){return f(this)[e](g,h,i)}}(c,s)
case 4:return function(e,f){return function(g,h,i,j){return f(this)[e](g,h,i,j)}}(c,s)
case 5:return function(e,f){return function(g,h,i,j,k){return f(this)[e](g,h,i,j,k)}}(c,s)
default:return function(e,f){return function(){return e.apply(f(this),arguments)}}(d,s)}},
fd(a,b,c,d){if(c)return A.hA(a,b,d)
return A.hy(b.length,d,a,b)},
hz(a,b,c,d){var s=A.fb,r=A.hw
switch(b?-1:a){case 0:throw A.b(new A.cs("Intercepted function with no arguments."))
case 1:return function(e,f,g){return function(){return f(this)[e](g(this))}}(c,r,s)
case 2:return function(e,f,g){return function(h){return f(this)[e](g(this),h)}}(c,r,s)
case 3:return function(e,f,g){return function(h,i){return f(this)[e](g(this),h,i)}}(c,r,s)
case 4:return function(e,f,g){return function(h,i,j){return f(this)[e](g(this),h,i,j)}}(c,r,s)
case 5:return function(e,f,g){return function(h,i,j,k){return f(this)[e](g(this),h,i,j,k)}}(c,r,s)
case 6:return function(e,f,g){return function(h,i,j,k,l){return f(this)[e](g(this),h,i,j,k,l)}}(c,r,s)
default:return function(e,f,g){return function(){var q=[g(this)]
Array.prototype.push.apply(q,arguments)
return e.apply(f(this),q)}}(d,r,s)}},
hA(a,b,c){var s,r
if($.f9==null)$.f9=A.f8("interceptor")
if($.fa==null)$.fa=A.f8("receiver")
s=b.length
r=A.hz(s,c,a,b)
return r},
eZ(a){return A.hB(a)},
hv(a,b){return A.bX(v.typeUniverse,A.b4(a.a),b)},
fb(a){return a.a},
hw(a){return a.b},
f8(a){var s,r,q,p=new A.aF("receiver","interceptor"),o=Object.getOwnPropertyNames(p)
o.$flags=1
s=o
for(o=s.length,r=0;r<o;++r){q=s[r]
if(p[q]===a)return q}throw A.b(A.c3("Field name "+a+" not found.",null))},
en(a){return v.getIsolateTag(a)},
jP(a,b,c){Object.defineProperty(a,b,{value:c,enumerable:false,writable:true,configurable:true})},
jk(a){var s,r,q,p,o,n=A.a1($.h7.$1(a)),m=$.em[n]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.es[n]
if(s!=null)return s
r=v.interceptorsByTag[n]
if(r==null){q=A.ed($.h1.$2(a,n))
if(q!=null){m=$.em[q]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.es[q]
if(s!=null)return s
r=v.interceptorsByTag[q]
n=q}}if(r==null)return null
s=r.prototype
p=n[0]
if(p==="!"){m=A.et(s)
$.em[n]=m
Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}if(p==="~"){$.es[n]=s
return s}if(p==="-"){o=A.et(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}if(p==="+")return A.h9(a,s)
if(p==="*")throw A.b(A.fy(n))
if(v.leafTags[n]===true){o=A.et(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}else return A.h9(a,s)},
h9(a,b){var s=Object.getPrototypeOf(a)
Object.defineProperty(s,v.dispatchPropertyName,{value:J.f3(b,s,null,null),enumerable:false,writable:true,configurable:true})
return b},
et(a){return J.f3(a,!1,null,!!a.$iK)},
jm(a,b,c){var s=b.prototype
if(v.leafTags[a]===true)return A.et(s)
else return J.f3(s,c,null,null)},
jg(){if(!0===$.f1)return
$.f1=!0
A.jh()},
jh(){var s,r,q,p,o,n,m,l
$.em=Object.create(null)
$.es=Object.create(null)
A.jf()
s=v.interceptorsByTag
r=Object.getOwnPropertyNames(s)
if(typeof window!="undefined"){window
q=function(){}
for(p=0;p<r.length;++p){o=r[p]
n=$.hb.$1(o)
if(n!=null){m=A.jm(o,s[o],n)
if(m!=null){Object.defineProperty(n,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
q.prototype=n}}}}for(p=0;p<r.length;++p){o=r[p]
if(/^[A-Za-z_]/.test(o)){l=s[o]
s["!"+o]=l
s["~"+o]=l
s["-"+o]=l
s["+"+o]=l
s["*"+o]=l}}},
jf(){var s,r,q,p,o,n,m=B.G()
m=A.b3(B.H,A.b3(B.I,A.b3(B.u,A.b3(B.u,A.b3(B.J,A.b3(B.K,A.b3(B.L(B.t),m)))))))
if(typeof dartNativeDispatchHooksTransformer!="undefined"){s=dartNativeDispatchHooksTransformer
if(typeof s=="function")s=[s]
if(Array.isArray(s))for(r=0;r<s.length;++r){q=s[r]
if(typeof q=="function")m=q(m)||m}}p=m.getTag
o=m.getUnknownTag
n=m.prototypeForTag
$.h7=new A.ep(p)
$.h1=new A.eq(o)
$.hb=new A.er(n)},
b3(a,b){return a(b)||b},
j7(a,b){var s=b.length,r=v.rttc[""+s+";"+a]
if(r==null)return null
if(s===0)return r
if(s===r.length)return r.apply(null,b)
return r(b)},
ja(a){if(a.indexOf("$",0)>=0)return a.replace(/\$/g,"$$$$")
return a},
hc(a){if(/[[\]{}()*+?.\\^$|]/.test(a))return a.replace(/[[\]{}()*+?.\\^$|]/g,"\\$&")
return a},
f4(a,b,c){var s=A.jq(a,b,c)
return s},
jq(a,b,c){var s,r,q
if(b===""){if(a==="")return c
s=a.length
for(r=c,q=0;q<s;++q)r=r+a[q]+c
return r.charCodeAt(0)==0?r:r}if(a.indexOf(b,0)<0)return a
if(a.length<500||c.indexOf("$",0)>=0)return a.split(b).join(c)
return a.replace(new RegExp(A.hc(b),"g"),A.ja(c))},
bN:function bN(a,b){this.a=a
this.b=b},
b9:function b9(){},
ba:function ba(a,b,c){this.a=a
this.b=b
this.$ti=c},
bH:function bH(a,b){this.a=a
this.$ti=b},
bI:function bI(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
bx:function bx(){},
dj:function dj(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
bt:function bt(){},
cm:function cm(a,b,c){this.a=a
this.b=b
this.c=c},
cz:function cz(a){this.a=a},
dd:function dd(a){this.a=a},
be:function be(a,b){this.a=a
this.b=b},
bO:function bO(a){this.a=a
this.b=null},
af:function af(){},
c7:function c7(){},
c8:function c8(){},
cx:function cx(){},
cv:function cv(){},
aF:function aF(a,b){this.a=a
this.b=b},
cs:function cs(a){this.a=a},
ap:function ap(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
d6:function d6(a,b){this.a=a
this.b=b
this.c=null},
bm:function bm(a,b){this.a=a
this.$ti=b},
aq:function aq(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=null
_.$ti=d},
bk:function bk(a,b){this.a=a
this.$ti=b},
bl:function bl(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=null
_.$ti=d},
ep:function ep(a){this.a=a},
eq:function eq(a){this.a=a},
er:function er(a){this.a=a},
az:function az(){},
b_:function b_(){},
jr(a){throw A.w(new A.aK("Field '"+a+"' has been assigned during initialization."),new Error())},
hW(){var s=new A.dF()
return s.b=s},
dF:function dF(){this.b=null},
fR(a){return a},
hI(a,b,c){var s=new DataView(a,b,c)
return s},
im(a,b,c){var s
if(!(a>>>0!==a))s=b>>>0!==b||a>b||b>c
else s=!0
if(s)throw A.b(A.j8(a,b,c))
return b},
ah:function ah(){},
aL:function aL(){},
bs:function bs(){},
cM:function cM(a){this.a=a},
aM:function aM(){},
aS:function aS(){},
bq:function bq(){},
br:function br(){},
aN:function aN(){},
aO:function aO(){},
aP:function aP(){},
aQ:function aQ(){},
aR:function aR(){},
aT:function aT(){},
aU:function aU(){},
at:function at(){},
ai:function ai(){},
bJ:function bJ(){},
bK:function bK(){},
bL:function bL(){},
bM:function bM(){},
eI(a,b){var s=b.c
return s==null?b.c=A.bV(a,"A",[b.x]):s},
fs(a){var s=a.w
if(s===6||s===7)return A.fs(a.x)
return s===11||s===12},
hL(a){return a.as},
al(a){return A.e6(v.typeUniverse,a,!1)},
aA(a1,a2,a3,a4){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=a2.w
switch(a0){case 5:case 1:case 2:case 3:case 4:return a2
case 6:s=a2.x
r=A.aA(a1,s,a3,a4)
if(r===s)return a2
return A.fH(a1,r,!0)
case 7:s=a2.x
r=A.aA(a1,s,a3,a4)
if(r===s)return a2
return A.fG(a1,r,!0)
case 8:q=a2.y
p=A.b2(a1,q,a3,a4)
if(p===q)return a2
return A.bV(a1,a2.x,p)
case 9:o=a2.x
n=A.aA(a1,o,a3,a4)
m=a2.y
l=A.b2(a1,m,a3,a4)
if(n===o&&l===m)return a2
return A.eM(a1,n,l)
case 10:k=a2.x
j=a2.y
i=A.b2(a1,j,a3,a4)
if(i===j)return a2
return A.fI(a1,k,i)
case 11:h=a2.x
g=A.aA(a1,h,a3,a4)
f=a2.y
e=A.iU(a1,f,a3,a4)
if(g===h&&e===f)return a2
return A.fF(a1,g,e)
case 12:d=a2.y
a4+=d.length
c=A.b2(a1,d,a3,a4)
o=a2.x
n=A.aA(a1,o,a3,a4)
if(c===d&&n===o)return a2
return A.eN(a1,n,c,!0)
case 13:b=a2.x
if(b<a4)return a2
a=a3[b-a4]
if(a==null)return a2
return a
default:throw A.b(A.c5("Attempted to substitute unexpected RTI kind "+a0))}},
b2(a,b,c,d){var s,r,q,p,o=b.length,n=A.e8(o)
for(s=!1,r=0;r<o;++r){q=b[r]
p=A.aA(a,q,c,d)
if(p!==q)s=!0
n[r]=p}return s?n:b},
iV(a,b,c,d){var s,r,q,p,o,n,m=b.length,l=A.e8(m)
for(s=!1,r=0;r<m;r+=3){q=b[r]
p=b[r+1]
o=b[r+2]
n=A.aA(a,o,c,d)
if(n!==o)s=!0
l.splice(r,3,q,p,n)}return s?l:b},
iU(a,b,c,d){var s,r=b.a,q=A.b2(a,r,c,d),p=b.b,o=A.b2(a,p,c,d),n=b.c,m=A.iV(a,n,c,d)
if(q===r&&o===p&&m===n)return b
s=new A.cJ()
s.a=q
s.b=o
s.c=m
return s},
z(a,b){a[v.arrayRti]=b
return a},
f_(a){var s=a.$S
if(s!=null){if(typeof s=="number")return A.je(s)
return a.$S()}return null},
ji(a,b){var s
if(A.fs(b))if(a instanceof A.af){s=A.f_(a)
if(s!=null)return s}return A.b4(a)},
b4(a){if(a instanceof A.c)return A.o(a)
if(Array.isArray(a))return A.bZ(a)
return A.eR(J.ac(a))},
bZ(a){var s=a[v.arrayRti],r=t.gn
if(s==null)return r
if(s.constructor!==r.constructor)return r
return s},
o(a){var s=a.$ti
return s!=null?s:A.eR(a)},
eR(a){var s=a.constructor,r=s.$ccache
if(r!=null)return r
return A.ix(a,s)},
ix(a,b){var s=a instanceof A.af?Object.getPrototypeOf(Object.getPrototypeOf(a)).constructor:b,r=A.ie(v.typeUniverse,s.name)
b.$ccache=r
return r},
je(a){var s,r=v.types,q=r[a]
if(typeof q=="string"){s=A.e6(v.typeUniverse,q,!1)
r[a]=s
return s}return q},
h6(a){return A.a2(A.o(a))},
eW(a){var s
if(a instanceof A.az)return a.aP()
s=a instanceof A.af?A.f_(a):null
if(s!=null)return s
if(t.dm.b(a))return J.b6(a).a
if(Array.isArray(a))return A.bZ(a)
return A.b4(a)},
a2(a){var s=a.r
return s==null?a.r=new A.e5(a):s},
jb(a,b){var s,r,q=b,p=q.length
if(p===0)return t.bQ
if(0>=p)return A.h(q,0)
s=A.bX(v.typeUniverse,A.eW(q[0]),"@<0>")
for(r=1;r<p;++r){if(!(r<q.length))return A.h(q,r)
s=A.fK(v.typeUniverse,s,A.eW(q[r]))}return A.bX(v.typeUniverse,s,a)},
Y(a){return A.a2(A.e6(v.typeUniverse,a,!1))},
iw(a){var s=this
s.b=A.iS(s)
return s.b(a)},
iS(a){var s,r,q,p,o
if(a===t.K)return A.iF
if(A.aB(a))return A.iJ
s=a.w
if(s===6)return A.iu
if(s===1)return A.fX
if(s===7)return A.iA
r=A.iR(a)
if(r!=null)return r
if(s===8){q=a.x
if(a.y.every(A.aB)){a.f="$i"+q
if(q==="m")return A.iD
if(a===t.m)return A.iC
return A.iI}}else if(s===10){p=A.j7(a.x,a.y)
o=p==null?A.fX:p
return o==null?A.a6(o):o}return A.is},
iR(a){if(a.w===8){if(a===t.S)return A.eT
if(a===t.i||a===t.o)return A.iE
if(a===t.N)return A.iH
if(a===t.y)return A.cQ}return null},
iv(a){var s=this,r=A.ir
if(A.aB(s))r=A.ij
else if(s===t.K)r=A.a6
else if(A.b5(s)){r=A.it
if(s===t.h6)r=A.cO
else if(s===t.c8)r=A.ed
else if(s===t.u)r=A.ih
else if(s===t.cg)r=A.fP
else if(s===t.cD)r=A.ii
else if(s===t.bX)r=A.fN}else if(s===t.S)r=A.G
else if(s===t.N)r=A.a1
else if(s===t.y)r=A.eO
else if(s===t.o)r=A.fO
else if(s===t.i)r=A.ec
else if(s===t.m)r=A.H
s.a=r
return s.a(a)},
is(a){var s=this
if(a==null)return A.b5(s)
return A.jj(v.typeUniverse,A.ji(a,s),s)},
iu(a){if(a==null)return!0
return this.x.b(a)},
iI(a){var s,r=this
if(a==null)return A.b5(r)
s=r.f
if(a instanceof A.c)return!!a[s]
return!!J.ac(a)[s]},
iD(a){var s,r=this
if(a==null)return A.b5(r)
if(typeof a!="object")return!1
if(Array.isArray(a))return!0
s=r.f
if(a instanceof A.c)return!!a[s]
return!!J.ac(a)[s]},
iC(a){var s=this
if(a==null)return!1
if(typeof a=="object"){if(a instanceof A.c)return!!a[s.f]
return!0}if(typeof a=="function")return!0
return!1},
fW(a){if(typeof a=="object"){if(a instanceof A.c)return t.m.b(a)
return!0}if(typeof a=="function")return!0
return!1},
ir(a){var s=this
if(a==null){if(A.b5(s))return a}else if(s.b(a))return a
throw A.w(A.fS(a,s),new Error())},
it(a){var s=this
if(a==null||s.b(a))return a
throw A.w(A.fS(a,s),new Error())},
fS(a,b){return new A.bT("TypeError: "+A.fz(a,A.C(b,null)))},
fz(a,b){return A.cf(a)+": type '"+A.C(A.eW(a),null)+"' is not a subtype of type '"+b+"'"},
S(a,b){return new A.bT("TypeError: "+A.fz(a,b))},
iA(a){var s=this
return s.x.b(a)||A.eI(v.typeUniverse,s).b(a)},
iF(a){return a!=null},
a6(a){if(a!=null)return a
throw A.w(A.S(a,"Object"),new Error())},
iJ(a){return!0},
ij(a){return a},
fX(a){return!1},
cQ(a){return!0===a||!1===a},
eO(a){if(!0===a)return!0
if(!1===a)return!1
throw A.w(A.S(a,"bool"),new Error())},
ih(a){if(!0===a)return!0
if(!1===a)return!1
if(a==null)return a
throw A.w(A.S(a,"bool?"),new Error())},
ec(a){if(typeof a=="number")return a
throw A.w(A.S(a,"double"),new Error())},
ii(a){if(typeof a=="number")return a
if(a==null)return a
throw A.w(A.S(a,"double?"),new Error())},
eT(a){return typeof a=="number"&&Math.floor(a)===a},
G(a){if(typeof a=="number"&&Math.floor(a)===a)return a
throw A.w(A.S(a,"int"),new Error())},
cO(a){if(typeof a=="number"&&Math.floor(a)===a)return a
if(a==null)return a
throw A.w(A.S(a,"int?"),new Error())},
iE(a){return typeof a=="number"},
fO(a){if(typeof a=="number")return a
throw A.w(A.S(a,"num"),new Error())},
fP(a){if(typeof a=="number")return a
if(a==null)return a
throw A.w(A.S(a,"num?"),new Error())},
iH(a){return typeof a=="string"},
a1(a){if(typeof a=="string")return a
throw A.w(A.S(a,"String"),new Error())},
ed(a){if(typeof a=="string")return a
if(a==null)return a
throw A.w(A.S(a,"String?"),new Error())},
H(a){if(A.fW(a))return a
throw A.w(A.S(a,"JSObject"),new Error())},
fN(a){if(a==null)return a
if(A.fW(a))return a
throw A.w(A.S(a,"JSObject?"),new Error())},
fZ(a,b){var s,r,q
for(s="",r="",q=0;q<a.length;++q,r=", ")s+=r+A.C(a[q],b)
return s},
iN(a,b){var s,r,q,p,o,n,m=a.x,l=a.y
if(""===m)return"("+A.fZ(l,b)+")"
s=l.length
r=m.split(",")
q=r.length-s
for(p="(",o="",n=0;n<s;++n,o=", "){p+=o
if(q===0)p+="{"
p+=A.C(l[n],b)
if(q>=0)p+=" "+r[q];++q}return p+"})"},
fT(a3,a4,a5){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1=", ",a2=null
if(a5!=null){s=a5.length
if(a4==null)a4=A.z([],t.s)
else a2=a4.length
r=a4.length
for(q=s;q>0;--q)B.a.j(a4,"T"+(r+q))
for(p=t.X,o="<",n="",q=0;q<s;++q,n=a1){m=a4.length
l=m-1-q
if(!(l>=0))return A.h(a4,l)
o=o+n+a4[l]
k=a5[q]
j=k.w
if(!(j===2||j===3||j===4||j===5||k===p))o+=" extends "+A.C(k,a4)}o+=">"}else o=""
p=a3.x
i=a3.y
h=i.a
g=h.length
f=i.b
e=f.length
d=i.c
c=d.length
b=A.C(p,a4)
for(a="",a0="",q=0;q<g;++q,a0=a1)a+=a0+A.C(h[q],a4)
if(e>0){a+=a0+"["
for(a0="",q=0;q<e;++q,a0=a1)a+=a0+A.C(f[q],a4)
a+="]"}if(c>0){a+=a0+"{"
for(a0="",q=0;q<c;q+=3,a0=a1){a+=a0
if(d[q+1])a+="required "
a+=A.C(d[q+2],a4)+" "+d[q]}a+="}"}if(a2!=null){a4.toString
a4.length=a2}return o+"("+a+") => "+b},
C(a,b){var s,r,q,p,o,n,m,l=a.w
if(l===5)return"erased"
if(l===2)return"dynamic"
if(l===3)return"void"
if(l===1)return"Never"
if(l===4)return"any"
if(l===6){s=a.x
r=A.C(s,b)
q=s.w
return(q===11||q===12?"("+r+")":r)+"?"}if(l===7)return"FutureOr<"+A.C(a.x,b)+">"
if(l===8){p=A.iX(a.x)
o=a.y
return o.length>0?p+("<"+A.fZ(o,b)+">"):p}if(l===10)return A.iN(a,b)
if(l===11)return A.fT(a,b,null)
if(l===12)return A.fT(a.x,b,a.y)
if(l===13){n=a.x
m=b.length
n=m-1-n
if(!(n>=0&&n<m))return A.h(b,n)
return b[n]}return"?"},
iX(a){var s=A.hd(a)
if(s!=null)return s
return"minified:"+a},
ig(a,b){var s=a.tR[b]
while(typeof s=="string")s=a.tR[s]
return s},
ie(a,b){var s,r,q,p,o,n=a.eT,m=n[b]
if(m==null)return A.e6(a,b,!1)
else if(typeof m=="number"){s=m
r=A.bW(a,5,"#")
q=A.e8(s)
for(p=0;p<s;++p)q[p]=r
o=A.bV(a,b,q)
n[b]=o
return o}else return m},
id(a,b){return A.fL(a.tR,b)},
ic(a,b){return A.fL(a.eT,b)},
e6(a,b,c){var s,r=a.eC,q=r.get(b)
if(q!=null)return q
s=A.fJ(a,null,b,!1)
r.set(b,s)
return s},
bX(a,b,c){var s,r,q=b.z
if(q==null)q=b.z=new Map()
s=q.get(c)
if(s!=null)return s
r=A.fJ(a,b,c,!0)
q.set(c,r)
return r},
fK(a,b,c){var s,r,q,p=b.Q
if(p==null)p=b.Q=new Map()
s=c.as
r=p.get(s)
if(r!=null)return r
q=A.eM(a,b,c.w===9?c.y:[c])
p.set(s,q)
return q},
fJ(a,b,c,d){return A.i4(A.hZ(a,b,c,d))},
ak(a,b){b.a=A.iv
b.b=A.iw
return b},
bW(a,b,c){var s,r,q=a.eC.get(c)
if(q!=null)return q
s=new A.Z(null,null)
s.w=b
s.as=c
r=A.ak(a,s)
a.eC.set(c,r)
return r},
fH(a,b,c){var s,r=b.as+"?",q=a.eC.get(r)
if(q!=null)return q
s=A.ia(a,b,r,c)
a.eC.set(r,s)
return s},
ia(a,b,c,d){var s,r,q
if(d){s=b.w
r=!0
if(!A.aB(b))if(!(b===t.P||b===t.T))if(s!==6)r=s===7&&A.b5(b.x)
if(r)return b
else if(s===1)return t.P}q=new A.Z(null,null)
q.w=6
q.x=b
q.as=c
return A.ak(a,q)},
fG(a,b,c){var s,r=b.as+"/",q=a.eC.get(r)
if(q!=null)return q
s=A.i8(a,b,r,c)
a.eC.set(r,s)
return s},
i8(a,b,c,d){var s,r
if(d){s=b.w
if(A.aB(b)||b===t.K)return b
else if(s===1)return A.bV(a,"A",[b])
else if(b===t.P||b===t.T)return t.eH}r=new A.Z(null,null)
r.w=7
r.x=b
r.as=c
return A.ak(a,r)},
ib(a,b){var s,r,q=""+b+"^",p=a.eC.get(q)
if(p!=null)return p
s=new A.Z(null,null)
s.w=13
s.x=b
s.as=q
r=A.ak(a,s)
a.eC.set(q,r)
return r},
bU(a){var s,r,q,p=a.length
for(s="",r="",q=0;q<p;++q,r=",")s+=r+a[q].as
return s},
i7(a){var s,r,q,p,o,n=a.length
for(s="",r="",q=0;q<n;q+=3,r=","){p=a[q]
o=a[q+1]?"!":":"
s+=r+p+o+a[q+2].as}return s},
bV(a,b,c){var s,r,q,p=b
if(c.length>0)p+="<"+A.bU(c)+">"
s=a.eC.get(p)
if(s!=null)return s
r=new A.Z(null,null)
r.w=8
r.x=b
r.y=c
if(c.length>0)r.c=c[0]
r.as=p
q=A.ak(a,r)
a.eC.set(p,q)
return q},
eM(a,b,c){var s,r,q,p,o,n
if(b.w===9){s=b.x
r=b.y.concat(c)}else{r=c
s=b}q=s.as+(";<"+A.bU(r)+">")
p=a.eC.get(q)
if(p!=null)return p
o=new A.Z(null,null)
o.w=9
o.x=s
o.y=r
o.as=q
n=A.ak(a,o)
a.eC.set(q,n)
return n},
fI(a,b,c){var s,r,q="+"+(b+"("+A.bU(c)+")"),p=a.eC.get(q)
if(p!=null)return p
s=new A.Z(null,null)
s.w=10
s.x=b
s.y=c
s.as=q
r=A.ak(a,s)
a.eC.set(q,r)
return r},
fF(a,b,c){var s,r,q,p,o,n=b.as,m=c.a,l=m.length,k=c.b,j=k.length,i=c.c,h=i.length,g="("+A.bU(m)
if(j>0){s=l>0?",":""
g+=s+"["+A.bU(k)+"]"}if(h>0){s=l>0?",":""
g+=s+"{"+A.i7(i)+"}"}r=n+(g+")")
q=a.eC.get(r)
if(q!=null)return q
p=new A.Z(null,null)
p.w=11
p.x=b
p.y=c
p.as=r
o=A.ak(a,p)
a.eC.set(r,o)
return o},
eN(a,b,c,d){var s,r=b.as+("<"+A.bU(c)+">"),q=a.eC.get(r)
if(q!=null)return q
s=A.i9(a,b,c,r,d)
a.eC.set(r,s)
return s},
i9(a,b,c,d,e){var s,r,q,p,o,n,m,l
if(e){s=c.length
r=A.e8(s)
for(q=0,p=0;p<s;++p){o=c[p]
if(o.w===1){r[p]=o;++q}}if(q>0){n=A.aA(a,b,r,0)
m=A.b2(a,c,r,0)
return A.eN(a,n,m,c!==m)}}l=new A.Z(null,null)
l.w=12
l.x=b
l.y=c
l.as=d
return A.ak(a,l)},
hZ(a,b,c,d){return{u:a,e:b,r:c,s:[],p:0,n:d}},
i4(a){var s,r,q,p,o,n,m,l=a.r,k=a.s
for(s=l.length,r=0;r<s;){q=l.charCodeAt(r)
if(q>=48&&q<=57)r=A.i0(r+1,q,l,k)
else if((((q|32)>>>0)-97&65535)<26||q===95||q===36||q===124)r=A.fB(a,r,l,k,!1)
else if(q===46)r=A.fB(a,r,l,k,!0)
else{++r
switch(q){case 44:break
case 58:k.push(!1)
break
case 33:k.push(!0)
break
case 59:k.push(A.ay(a.u,a.e,k.pop()))
break
case 94:k.push(A.ib(a.u,k.pop()))
break
case 35:k.push(A.bW(a.u,5,"#"))
break
case 64:k.push(A.bW(a.u,2,"@"))
break
case 126:k.push(A.bW(a.u,3,"~"))
break
case 60:k.push(a.p)
a.p=k.length
break
case 62:A.i2(a,k)
break
case 38:A.i1(a,k)
break
case 63:p=a.u
k.push(A.fH(p,A.ay(p,a.e,k.pop()),a.n))
break
case 47:p=a.u
k.push(A.fG(p,A.ay(p,a.e,k.pop()),a.n))
break
case 40:k.push(-3)
k.push(a.p)
a.p=k.length
break
case 41:A.i_(a,k)
break
case 91:k.push(a.p)
a.p=k.length
break
case 93:o=k.splice(a.p)
A.fC(a.u,a.e,o)
a.p=k.pop()
k.push(o)
k.push(-1)
break
case 123:k.push(a.p)
a.p=k.length
break
case 125:o=k.splice(a.p)
A.i5(a.u,a.e,o)
a.p=k.pop()
k.push(o)
k.push(-2)
break
case 43:n=l.indexOf("(",r)
k.push(l.substring(r,n))
k.push(-4)
k.push(a.p)
a.p=k.length
r=n+1
break
default:throw"Bad character "+q}}}m=k.pop()
return A.ay(a.u,a.e,m)},
i0(a,b,c,d){var s,r,q=b-48
for(s=c.length;a<s;++a){r=c.charCodeAt(a)
if(!(r>=48&&r<=57))break
q=q*10+(r-48)}d.push(q)
return a},
fB(a,b,c,d,e){var s,r,q,p,o,n,m=b+1
for(s=c.length;m<s;++m){r=c.charCodeAt(m)
if(r===46){if(e)break
e=!0}else{if(!((((r|32)>>>0)-97&65535)<26||r===95||r===36||r===124))q=r>=48&&r<=57
else q=!0
if(!q)break}}p=c.substring(b,m)
if(e){s=a.u
o=a.e
if(o.w===9)o=o.x
n=A.ig(s,o.x)[p]
if(n==null)A.ad('No "'+p+'" in "'+A.hL(o)+'"')
d.push(A.bX(s,o,n))}else d.push(p)
return m},
i2(a,b){var s,r=a.u,q=A.fA(a,b),p=b.pop()
if(typeof p=="string")b.push(A.bV(r,p,q))
else{s=A.ay(r,a.e,p)
switch(s.w){case 11:b.push(A.eN(r,s,q,a.n))
break
default:b.push(A.eM(r,s,q))
break}}},
i_(a,b){var s,r,q,p=a.u,o=b.pop(),n=null,m=null
if(typeof o=="number")switch(o){case-1:n=b.pop()
break
case-2:m=b.pop()
break
default:b.push(o)
break}else b.push(o)
s=A.fA(a,b)
o=b.pop()
switch(o){case-3:o=b.pop()
if(n==null)n=p.sEA
if(m==null)m=p.sEA
r=A.ay(p,a.e,o)
q=new A.cJ()
q.a=s
q.b=n
q.c=m
b.push(A.fF(p,r,q))
return
case-4:b.push(A.fI(p,b.pop(),s))
return
default:throw A.b(A.c5("Unexpected state under `()`: "+A.j(o)))}},
i1(a,b){var s=b.pop()
if(0===s){b.push(A.bW(a.u,1,"0&"))
return}if(1===s){b.push(A.bW(a.u,4,"1&"))
return}throw A.b(A.c5("Unexpected extended operation "+A.j(s)))},
fA(a,b){var s=b.splice(a.p)
A.fC(a.u,a.e,s)
a.p=b.pop()
return s},
ay(a,b,c){if(typeof c=="string")return A.bV(a,c,a.sEA)
else if(typeof c=="number"){b.toString
return A.i3(a,b,c)}else return c},
fC(a,b,c){var s,r=c.length
for(s=0;s<r;++s)c[s]=A.ay(a,b,c[s])},
i5(a,b,c){var s,r=c.length
for(s=2;s<r;s+=3)c[s]=A.ay(a,b,c[s])},
i3(a,b,c){var s,r,q=b.w
if(q===9){if(c===0)return b.x
s=b.y
r=s.length
if(c<=r)return s[c-1]
c-=r
b=b.x
q=b.w}else if(c===0)return b
if(q!==8)throw A.b(A.c5("Indexed base must be an interface type"))
s=b.y
if(c<=s.length)return s[c-1]
throw A.b(A.c5("Bad index "+c+" for "+b.i(0)))},
jj(a,b,c){var s,r=b.d
if(r==null)r=b.d=new Map()
s=r.get(c)
if(s==null){s=A.v(a,b,null,c,null)
r.set(c,s)}return s},
v(a,b,c,d,e){var s,r,q,p,o,n,m,l,k,j,i
if(b===d)return!0
if(A.aB(d))return!0
s=b.w
if(s===4)return!0
if(A.aB(b))return!1
if(b.w===1)return!0
r=s===13
if(r)if(A.v(a,c[b.x],c,d,e))return!0
q=d.w
p=t.P
if(b===p||b===t.T){if(q===7)return A.v(a,b,c,d.x,e)
return d===p||d===t.T||q===6}if(d===t.K){if(s===7)return A.v(a,b.x,c,d,e)
return s!==6}if(s===7){if(!A.v(a,b.x,c,d,e))return!1
return A.v(a,A.eI(a,b),c,d,e)}if(s===6)return A.v(a,p,c,d,e)&&A.v(a,b.x,c,d,e)
if(q===7){if(A.v(a,b,c,d.x,e))return!0
return A.v(a,b,c,A.eI(a,d),e)}if(q===6)return A.v(a,b,c,p,e)||A.v(a,b,c,d.x,e)
if(r)return!1
p=s!==11
if((!p||s===12)&&d===t.Z)return!0
o=s===10
if(o&&d===t.L)return!0
if(q===12){if(b===t.g)return!0
if(s!==12)return!1
n=b.y
m=d.y
l=n.length
if(l!==m.length)return!1
c=c==null?n:n.concat(c)
e=e==null?m:m.concat(e)
for(k=0;k<l;++k){j=n[k]
i=m[k]
if(!A.v(a,j,c,i,e)||!A.v(a,i,e,j,c))return!1}return A.fV(a,b.x,c,d.x,e)}if(q===11){if(b===t.g)return!0
if(p)return!1
return A.fV(a,b,c,d,e)}if(s===8){if(q!==8)return!1
return A.iB(a,b,c,d,e)}if(o&&q===10)return A.iG(a,b,c,d,e)
return!1},
fV(a3,a4,a5,a6,a7){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2
if(!A.v(a3,a4.x,a5,a6.x,a7))return!1
s=a4.y
r=a6.y
q=s.a
p=r.a
o=q.length
n=p.length
if(o>n)return!1
m=n-o
l=s.b
k=r.b
j=l.length
i=k.length
if(o+j<n+i)return!1
for(h=0;h<o;++h){g=q[h]
if(!A.v(a3,p[h],a7,g,a5))return!1}for(h=0;h<m;++h){g=l[h]
if(!A.v(a3,p[o+h],a7,g,a5))return!1}for(h=0;h<i;++h){g=l[m+h]
if(!A.v(a3,k[h],a7,g,a5))return!1}f=s.c
e=r.c
d=f.length
c=e.length
for(b=0,a=0;a<c;a+=3){a0=e[a]
for(;;){if(b>=d)return!1
a1=f[b]
b+=3
if(a0<a1)return!1
a2=f[b-2]
if(a1<a0){if(a2)return!1
continue}g=e[a+1]
if(a2&&!g)return!1
g=f[b-1]
if(!A.v(a3,e[a+2],a7,g,a5))return!1
break}}while(b<d){if(f[b+1])return!1
b+=3}return!0},
iB(a,b,c,d,e){var s,r,q,p,o,n=b.x,m=d.x
while(n!==m){s=a.tR[n]
if(s==null)return!1
if(typeof s=="string"){n=s
continue}r=s[m]
if(r==null)return!1
q=r.length
p=q>0?new Array(q):v.typeUniverse.sEA
for(o=0;o<q;++o)p[o]=A.bX(a,b,r[o])
return A.fM(a,p,null,c,d.y,e)}return A.fM(a,b.y,null,c,d.y,e)},
fM(a,b,c,d,e,f){var s,r=b.length
for(s=0;s<r;++s)if(!A.v(a,b[s],d,e[s],f))return!1
return!0},
iG(a,b,c,d,e){var s,r=b.y,q=d.y,p=r.length
if(p!==q.length)return!1
if(b.x!==d.x)return!1
for(s=0;s<p;++s)if(!A.v(a,r[s],c,q[s],e))return!1
return!0},
b5(a){var s=a.w,r=!0
if(!(a===t.P||a===t.T))if(!A.aB(a))if(s!==6)r=s===7&&A.b5(a.x)
return r},
aB(a){var s=a.w
return s===2||s===3||s===4||s===5||a===t.X},
fL(a,b){var s,r,q=Object.keys(b),p=q.length
for(s=0;s<p;++s){r=q[s]
a[r]=b[r]}},
e8(a){return a>0?new Array(a):v.typeUniverse.sEA},
Z:function Z(a,b){var _=this
_.a=a
_.b=b
_.r=_.f=_.d=_.c=null
_.w=0
_.as=_.Q=_.z=_.y=_.x=null},
cJ:function cJ(){this.c=this.b=this.a=null},
e5:function e5(a){this.a=a},
cI:function cI(){},
bT:function bT(a){this.a=a},
hR(){var s,r,q
if(self.scheduleImmediate!=null)return A.iZ()
if(self.MutationObserver!=null&&self.document!=null){s={}
r=self.document.createElement("div")
q=self.document.createElement("span")
s.a=null
new self.MutationObserver(A.c2(new A.dB(s),1)).observe(r,{childList:true})
return new A.dA(s,r,q)}else if(self.setImmediate!=null)return A.j_()
return A.j0()},
hS(a){self.scheduleImmediate(A.c2(new A.dC(t.M.a(a)),0))},
hT(a){self.setImmediate(A.c2(new A.dD(t.M.a(a)),0))},
hU(a){A.fw(B.Q,t.M.a(a))},
fw(a,b){return A.i6(a.a/1000|0,b)},
i6(a,b){var s=new A.e3()
s.bi(a,b)
return s},
W(a){return new A.bE(new A.e($.f,a.h("e<0>")),a.h("bE<0>"))},
V(a,b){a.$2(0,null)
b.b=!0
return b.a},
B(a,b){A.ik(a,b)},
U(a,b){b.a5(a)},
T(a,b){b.av(A.D(a),A.I(a))},
ik(a,b){var s,r,q=new A.ee(b),p=new A.ef(b)
if(a instanceof A.e)a.aZ(q,p,t.z)
else{s=t.z
if(a instanceof A.e)a.U(q,p,s)
else{r=new A.e($.f,t._)
r.a=8
r.c=a
r.aZ(q,p,s)}}},
X(a){var s=function(b,c){return function(d,e){while(true){try{b(d,e)
break}catch(q){e=q
d=c}}}}(a,1),r=$.f
return r.ai(r,t.as.a(new A.ek(s)),t.H,t.S,t.z)},
fE(a,b,c){return 0},
c6(a){var s
if(t.C.b(a)){s=a.gK()
if(s!=null)return s}return B.e},
hE(a,b){var s,r,q,p,o,n,m,l=null
try{l=a.$0()}catch(q){s=A.D(q)
r=A.I(q)
p=new A.e($.f,b.h("e<0>"))
o=s
n=r
m=A.fU(o,n)
o=new A.x(o,n==null?A.c6(o):n)
p.M(o)
return p}return b.h("A<0>").b(l)?l:A.dH(l,b)},
fU(a,b){var s=$.f
if(s===B.b)return null
s.bo(s,a,b)
return null},
iy(a,b){if($.f!==B.b)A.fU(a,b)
if(b==null)if(t.C.b(a)){b=a.gK()
if(b==null){A.fq(a,B.e)
b=B.e}}else b=B.e
else if(t.C.b(a))A.fq(a,b)
return new A.x(a,b)},
dH(a,b){var s=new A.e($.f,b.h("e<0>"))
b.a(a)
s.a=8
s.c=a
return s},
dL(a,b,c){var s,r,q,p,o,n={},m=n.a=a
for(s=t._;r=m.a,(r&4)!==0;m=a){a=s.a(m.c)
n.a=a}if(m===b){s=A.hM()
b.M(new A.x(new A.a3(!0,m,null,"Cannot complete a future with itself"),s))
return}q=b.a&1
s=m.a=r|q
if((s&24)===0){p=t.F.a(b.c)
b.a=b.a&1|4
b.c=m
m.aV(p)
return}if(!c)if(b.c==null)m=(s&16)===0||q!==0
else m=!1
else m=!0
if(m){p=b.P()
b.Y(n.a)
A.ax(b,p)
return}b.a^=2
o=b.b
o.S(o,new A.dM(n,b))},
ax(a,b){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e={},d=e.a=a
for(s=t.n,r=t.F;;){q={}
p=d.a
o=(p&16)===0
n=!o
if(b==null){if(n&&(p&1)===0){m=s.a(d.c)
d=d.b
d.O(d,m.a,m.b)}return}q.a=b
l=b.a
for(d=b;l!=null;d=l,l=k){d.a=null
A.ax(e.a,d)
q.a=l
k=l.a}j=e.a.c
q.b=n
q.c=j
if(o){p=d.c
p=(p&1)!==0||(p&15)===8}else p=!0
if(p){i=d.b.b
h=$.f
if(h!==i)$.f=i
else h=null
d=d.c
if((d&15)===8)new A.dQ(q,e,n).$0()
else if(o){if((d&1)!==0)new A.dP(q,j).$0()}else if((d&2)!==0)new A.dO(e,q).$0()
if(h!=null)$.f=h
d=q.c
if(d instanceof A.e){p=q.a.$ti
p=p.h("A<2>").b(d)||!p.y[1].b(d)}else p=!1
if(p){g=q.a.b
if((d.a&24)!==0){f=r.a(g.c)
g.c=null
b=g.a_(f)
g.a=d.a&30|g.a&1
g.c=d.c
e.a=d
continue}else A.dL(d,g,!0)
return}}g=q.a.b
f=r.a(g.c)
g.c=null
b=g.a_(f)
d=q.b
p=q.c
if(!d){g.$ti.c.a(p)
g.a=8
g.c=p}else{s.a(p)
g.a=g.a&1|16
g.c=p}e.a=g
d=g}},
iO(a,b){var s=t.Q
if(s.b(a))return b.ai(b,s.a(a),t.z,t.K,t.l)
s=t.v
if(s.b(a))return b.Z(b,s.a(a),t.z,t.K)
throw A.b(A.aE(a,"onError",u.c))},
iL(){var s,r
for(s=$.b1;s!=null;s=$.b1){$.c0=null
r=s.b
$.b1=r
if(r==null)$.c_=null
s.a.$0()}},
iT(){$.eS=!0
try{A.iL()}finally{$.c0=null
$.eS=!1
if($.b1!=null)$.f6().$1(A.h2())}},
h_(a){var s=new A.cE(a),r=$.c_
if(r==null){$.b1=$.c_=s
if(!$.eS)$.f6().$1(A.h2())}else $.c_=r.b=s},
iQ(a){var s,r,q,p=$.b1
if(p==null){A.h_(a)
$.c0=$.c_
return}s=new A.cE(a)
r=$.c0
if(r==null){s.b=p
$.b1=$.c0=s}else{q=r.b
s.b=q
$.c0=r.b=s
if(q==null)$.c_=s}},
jp(a){var s=$.f
if(B.b===s){A.eU(B.b,a)
return}A.eU(s,s.I(s,a,t.H))
return},
jz(a,b){A.eY(a,"stream",t.K)
return new A.cK(b.h("cK<0>"))},
fu(a){var s=null
return new A.aX(s,s,s,s,a.h("aX<0>"))},
eV(a){return},
hV(a,b){if(b==null)b=A.j1()
if(t.da.b(b))return a.ai(a,t.Q.a(b),t.z,t.K,t.l)
if(t.d5.b(b))return a.Z(a,t.v.a(b),t.z,t.K)
throw A.b(A.c3("handleError callback must take either an Object (the error), or both an Object (the error) and a StackTrace.",null))},
iM(a,b){var s
A.a6(a)
t.l.a(b)
s=$.f
s.O(s,a,b)},
hO(a,b){var s=$.f
if(s===B.b)return s.aL(s,a,t.M.a(b))
return s.aL(s,a,t.M.a(s.bI(b)))},
iP(a,b){A.iQ(new A.eh(a,b))},
eU(a,b){if(B.b!==a)b=a.b1(b,t.H)
A.h_(b)},
dB:function dB(a){this.a=a},
dA:function dA(a,b,c){this.a=a
this.b=b
this.c=c},
dC:function dC(a){this.a=a},
dD:function dD(a){this.a=a},
e3:function e3(){this.b=null},
e4:function e4(a,b){this.a=a
this.b=b},
bE:function bE(a,b){this.a=a
this.b=!1
this.$ti=b},
ee:function ee(a){this.a=a},
ef:function ef(a){this.a=a},
ek:function ek(a){this.a=a},
bS:function bS(a,b){var _=this
_.a=a
_.e=_.d=_.c=_.b=null
_.$ti=b},
b0:function b0(a,b){this.a=a
this.$ti=b},
x:function x(a,b){this.a=a
this.b=b},
bG:function bG(){},
a5:function a5(a,b){this.a=a
this.$ti=b},
ab:function ab(a,b,c,d,e){var _=this
_.a=null
_.b=a
_.c=b
_.d=c
_.e=d
_.$ti=e},
e:function e(a,b){var _=this
_.a=0
_.b=a
_.c=null
_.$ti=b},
dI:function dI(a,b){this.a=a
this.b=b},
dN:function dN(a,b){this.a=a
this.b=b},
dM:function dM(a,b){this.a=a
this.b=b},
dK:function dK(a,b){this.a=a
this.b=b},
dJ:function dJ(a,b){this.a=a
this.b=b},
dQ:function dQ(a,b,c){this.a=a
this.b=b
this.c=c},
dR:function dR(a,b){this.a=a
this.b=b},
dS:function dS(a){this.a=a},
dP:function dP(a,b){this.a=a
this.b=b},
dO:function dO(a,b){this.a=a
this.b=b},
dT:function dT(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
dU:function dU(a,b,c){this.a=a
this.b=b
this.c=c},
dV:function dV(a,b){this.a=a
this.b=b},
cE:function cE(a){this.a=a
this.b=null},
bz:function bz(){},
dg:function dg(a,b){this.a=a
this.b=b},
dh:function dh(a,b){this.a=a
this.b=b},
bP:function bP(){},
e2:function e2(a){this.a=a},
e1:function e1(a){this.a=a},
cF:function cF(){},
aX:function aX(a,b,c,d,e){var _=this
_.a=null
_.b=0
_.c=null
_.d=a
_.e=b
_.f=c
_.r=d
_.$ti=e},
aY:function aY(a,b){this.a=a
this.$ti=b},
aZ:function aZ(a,b,c,d,e,f){var _=this
_.w=a
_.a=b
_.c=c
_.d=d
_.e=e
_.r=_.f=null
_.$ti=f},
bF:function bF(){},
dE:function dE(a){this.a=a},
bR:function bR(){},
aj:function aj(){},
av:function av(a,b){this.b=a
this.a=null
this.$ti=b},
cG:function cG(){},
a0:function a0(a){var _=this
_.a=0
_.c=_.b=null
_.$ti=a},
e_:function e_(a,b){this.a=a
this.b=b},
cK:function cK(a){this.$ti=a},
dx:function dx(){},
dz:function dz(a,b,c){this.a=a
this.b=b
this.c=c},
dy:function dy(a,b){this.a=a
this.b=b},
eh:function eh(a,b){this.a=a
this.b=b},
d7(a,b,c){return b.h("@<0>").t(c).h("fk<1,2>").a(A.jc(a,new A.ap(b.h("@<0>").t(c).h("ap<1,2>"))))},
eF(a,b){return new A.ap(a.h("@<0>").t(b).h("ap<1,2>"))},
eG(a){var s,r
if(A.f2(a))return"{...}"
s=new A.aW("")
try{r={}
B.a.j($.O,a)
s.a+="{"
r.a=!0
a.J(0,new A.da(r,s))
s.a+="}"}finally{if(0>=$.O.length)return A.h($.O,-1)
$.O.pop()}r=s.a
return r.charCodeAt(0)==0?r:r},
r:function r(){},
bo:function bo(){},
d9:function d9(a){this.a=a},
da:function da(a,b){this.a=a
this.b=b},
fj(a,b,c){return new A.bj(a,b)},
ip(a){return a.bd()},
hX(a,b){return new A.dX(a,[],A.j6())},
hY(a,b,c){var s,r=new A.aW(""),q=A.hX(r,b)
q.a9(a)
s=r.a
return s.charCodeAt(0)==0?s:s},
c9:function c9(){},
cd:function cd(){},
bj:function bj(a,b){this.a=a
this.b=b},
co:function co(a,b){this.a=a
this.b=b},
cn:function cn(){},
d5:function d5(a){this.b=a},
dY:function dY(){},
dZ:function dZ(a,b){this.a=a
this.b=b},
dX:function dX(a,b,c){this.c=a
this.a=b
this.b=c},
dp:function dp(){},
e7:function e7(a){this.b=0
this.c=a},
hC(a,b){a=A.w(a,new Error())
if(a==null)a=A.a6(a)
a.stack=b.i(0)
throw a},
hG(a,b,c){var s,r
if(a>4294967295)A.ad(A.bw(a,0,4294967295,"length",null))
s=A.z(new Array(a),c.h("p<0>"))
s.$flags=1
r=s
return r},
d8(a,b,c){var s,r,q=A.z([],c.h("p<0>"))
for(s=a.length,r=0;r<a.length;a.length===s||(0,A.an)(a),++r)B.a.j(q,c.a(a[r]))
if(b)return q
q.$flags=1
return q},
fl(a,b){var s,r
if(Array.isArray(a))return A.z(a.slice(0),b.h("p<0>"))
s=A.z([],b.h("p<0>"))
for(r=J.eB(a);r.n();)B.a.j(s,r.gq())
return s},
fv(a,b,c){var s=J.eB(b)
if(!s.n())return a
if(c.length===0){do a+=A.j(s.gq())
while(s.n())}else{a+=A.j(s.gq())
while(s.n())a=a+c+A.j(s.gq())}return a},
hM(){return A.I(new Error())},
fg(a,b,c){var s,r,q
for(s=a.length,r=0;r<s;++r){q=a[r]
if(q.b===b)return q}throw A.b(A.aE(b,"name","No enum value with that name"))},
cf(a){if(typeof a=="number"||A.cQ(a)||a==null)return J.aD(a)
if(typeof a=="string")return JSON.stringify(a)
return A.fp(a)},
hD(a,b){A.eY(a,"error",t.K)
A.eY(b,"stackTrace",t.l)
A.hC(a,b)},
c5(a){return new A.c4(a)},
c3(a,b){return new A.a3(!1,null,b,a)},
aE(a,b,c){return new A.a3(!0,a,b,c)},
fr(a,b){return new A.bv(null,null,!0,a,b,"Value not in range")},
bw(a,b,c,d,e){return new A.bv(b,c,!0,a,d,"Invalid value")},
eH(a,b,c){if(0>a||a>c)throw A.b(A.bw(a,0,c,"start",null))
if(b!=null){if(a>b||b>c)throw A.b(A.bw(b,a,c,"end",null))
return b}return c},
hK(a,b){return a},
fh(a,b,c,d){return new A.ch(b,!0,a,d,"Index out of range")},
bD(a){return new A.bC(a)},
fy(a){return new A.cy(a)},
a8(a){return new A.au(a)},
cc(a){return new A.cb(a)},
eC(a){return new A.cg(a)},
hF(a,b,c){var s,r
if(A.f2(a)){if(b==="("&&c===")")return"(...)"
return b+"..."+c}s=A.z([],t.s)
B.a.j($.O,a)
try{A.iK(a,s)}finally{if(0>=$.O.length)return A.h($.O,-1)
$.O.pop()}r=A.fv(b,t.hf.a(s),", ")+c
return r.charCodeAt(0)==0?r:r},
fi(a,b,c){var s,r
if(A.f2(a))return b+"..."+c
s=new A.aW(b)
B.a.j($.O,a)
try{r=s
r.a=A.fv(r.a,a,", ")}finally{if(0>=$.O.length)return A.h($.O,-1)
$.O.pop()}s.a+=c
r=s.a
return r.charCodeAt(0)==0?r:r},
iK(a,b){var s,r,q,p,o,n,m,l=a.gu(a),k=0,j=0
for(;;){if(!(k<80||j<3))break
if(!l.n())return
s=A.j(l.gq())
B.a.j(b,s)
k+=s.length+2;++j}if(!l.n()){if(j<=5)return
if(0>=b.length)return A.h(b,-1)
r=b.pop()
if(0>=b.length)return A.h(b,-1)
q=b.pop()}else{p=l.gq();++j
if(!l.n()){if(j<=4){B.a.j(b,A.j(p))
return}r=A.j(p)
if(0>=b.length)return A.h(b,-1)
q=b.pop()
k+=r.length+2}else{o=l.gq();++j
for(;l.n();p=o,o=n){n=l.gq();++j
if(j>100){for(;;){if(!(k>75&&j>3))break
if(0>=b.length)return A.h(b,-1)
k-=b.pop().length+2;--j}B.a.j(b,"...")
return}}q=A.j(p)
r=A.j(o)
k+=r.length+q.length+4}}if(j>b.length+2){k+=5
m="..."}else m=null
for(;;){if(!(k>80&&b.length>3))break
if(0>=b.length)return A.h(b,-1)
k-=b.pop().length+2
if(m==null){k+=5
m="..."}}if(m!=null)B.a.j(b,m)
B.a.j(b,q)
B.a.j(b,r)},
fm(a,b,c,d,e){var s
if(B.d===c){s=B.c.gl(a)
b=J.P(b)
return A.di(A.M(A.M($.cT(),s),b))}if(B.d===d){s=B.c.gl(a)
b=J.P(b)
c=J.P(c)
return A.di(A.M(A.M(A.M($.cT(),s),b),c))}if(B.d===e){s=B.c.gl(a)
b=J.P(b)
c=J.P(c)
d=J.P(d)
return A.di(A.M(A.M(A.M(A.M($.cT(),s),b),c),d))}s=B.c.gl(a)
b=J.P(b)
c=J.P(c)
d=J.P(d)
e=J.P(e)
e=A.di(A.M(A.M(A.M(A.M(A.M($.cT(),s),b),c),d),e))
return e},
bb:function bb(a){this.a=a},
cH:function cH(){},
n:function n(){},
c4:function c4(a){this.a=a},
a9:function a9(){},
a3:function a3(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
bv:function bv(a,b,c,d,e,f){var _=this
_.e=a
_.f=b
_.a=c
_.b=d
_.c=e
_.d=f},
ch:function ch(a,b,c,d,e){var _=this
_.f=a
_.a=b
_.b=c
_.c=d
_.d=e},
bC:function bC(a){this.a=a},
cy:function cy(a){this.a=a},
au:function au(a){this.a=a},
cb:function cb(a){this.a=a},
cp:function cp(){},
by:function by(){},
dG:function dG(a){this.a=a},
cg:function cg(a){this.a=a},
d:function d(){},
F:function F(a,b,c){this.a=a
this.b=b
this.$ti=c},
t:function t(){},
c:function c(){},
cL:function cL(){},
aW:function aW(a){this.a=a},
dc:function dc(a){this.a=a},
cP(a){var s
if(typeof a=="function")throw A.b(A.c3("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d){return b(c,d,arguments.length)}}(A.il,a)
s[$.f5()]=a
return s},
il(a,b,c){t.Z.a(a)
if(A.G(c)>=1)return a.$1(b)
return a.$0()},
ha(a,b){var s=new A.e($.f,b.h("e<0>")),r=new A.a5(s,b.h("a5<0>"))
a.then(A.c2(new A.ev(r,b),1),A.c2(new A.ew(r),1))
return s},
ev:function ev(a,b){this.a=a
this.b=b},
ew:function ew(a){this.a=a},
j2(a,b){var s,r="codecString"
if(b.a6(r)){s=b.m(0,r)
s.toString
return s}A:{if(B.n===a){s="mp4a.40.2"
break A}if(B.o===a){s="opus"
break A}if(B.q===a){s="mp3"
break A}if(B.r===a){s="flac"
break A}if(B.p===a){s="vorbis"
break A}s=A.ad(A.bD("WebCodecs audio: no codec string for "+a.i(0)))}return s},
eJ(a){var s=0,r=A.W(t.g0),q,p,o,n,m,l,k
var $async$eJ=A.X(function(b,c){if(b===1)return A.T(c,r)
for(;;)switch(s){case 0:l=a.c
k=a.d
if(l==null||k==null)throw A.b(A.fe("webcodecs","WebCodecs audio decode requires sampleRate + channels in AudioDecoderConfig (WebCodecs does not derive them from the bitstream). Got sampleRate="+A.j(l)+" channels="+A.j(k)+"."))
p=new A.cA(A.z([],t.A))
o=A.j2(a.a,a.e)
p.a=A.H(new v.G.AudioDecoder({output:A.cP(new A.dr(p)),error:A.cP(new A.ds(p))}))
n=a.b
m=n!=null&&n.length!==0?{codec:o,sampleRate:l,numberOfChannels:k,description:new Uint8Array(A.fR(n))}:{codec:o,sampleRate:l,numberOfChannels:k}
p.a.configure(m)
p.a2()
q=p
s=1
break
case 1:return A.U(q,r)}})
return A.V($async$eJ,r)},
cA:function cA(a){var _=this
_.a=null
_.b=a
_.d=_.c=null},
dq:function dq(){},
dr:function dr(a){this.a=a},
ds:function ds(a){this.a=a},
jt(a,b){var s,r="codecString"
if(b.a6(r)){s=b.m(0,r)
s.toString
return s}A:{if(B.y===a){s="avc1.42E01E"
break A}if(B.z===a){s="hev1.1.6.L93.B0"
break A}if(B.C===a){s="vp8"
break A}if(B.B===a){s="vp09.00.10.08"
break A}if(B.A===a){s="av01.0.04M.08"
break A}s=A.ad(A.bD("WebCodecs: no default codec string for "+a.i(0)+". Supply one via backendOptions['codecString']."))}return s},
eK(a){var s=0,r=A.W(t.dD),q,p,o,n,m
var $async$eK=A.X(function(b,c){if(b===1)return A.T(c,r)
for(;;)switch(s){case 0:n=new A.cB(A.z([],t.t))
m=A.jt(a.a,a.x)
n.a=A.H(new v.G.VideoDecoder({output:A.cP(new A.du(n)),error:A.cP(new A.dv(n))}))
p=a.c
o=p!=null&&p.length!==0?{codec:m,description:new Uint8Array(A.fR(p))}:{codec:m}
n.a.configure(o)
n.a4()
q=n
s=1
break
case 1:return A.U(q,r)}})
return A.V($async$eK,r)},
cB:function cB(a){var _=this
_.a=null
_.b=a
_.d=_.c=null},
dt:function dt(){},
du:function du(a){this.a=a},
dv:function dv(a){this.a=a},
cC:function cC(a){this.a=a
this.b=!1},
c1(a){return A.j3(a)},
j3(a){var s=0,r=A.W(t.H),q=1,p=[],o,n,m,l,k,j
var $async$c1=A.X(function(b,c){if(b===1){p.push(c)
s=q}for(;;)switch(s){case 0:l={}
k=a.r
k.toString
t.I.a(k)
o=A.ed(k.m(0,"role"))
l.a=l.b=null
a.bR(new A.el(l,o,k))
s=2
return A.B(a.c.a,$async$c1)
case 2:q=4
k=l.b
k=k==null?null:k.v()
n=t.H
s=7
return A.B(k instanceof A.e?k:A.dH(k,n),$async$c1)
case 7:l=l.a
l=l==null?null:l.v()
s=8
return A.B(l instanceof A.e?l:A.dH(l,n),$async$c1)
case 8:q=1
s=6
break
case 4:q=3
j=p.pop()
s=6
break
case 3:s=1
break
case 6:return A.U(null,r)
case 1:return A.T(p.at(-1),r)}})
return A.V($async$c1,r)},
h0(a){var s
if(a==null)return null
s=a.b?null:a.a
if(s==null){a.v()
throw A.b(B.P)}return new A.aV(s)},
fY(a){var s,r,q,p=a.m(0,"options")
if(!t.I.b(p))return B.a0
s=t.N
s=A.eF(s,s)
for(r=p.ga8(),r=r.gu(r);r.n();){q=r.gq()
s.E(0,q.a,A.j(q.b))}return s},
jl(){A.jo(A.j4())
return null},
el:function el(a,b,c){this.a=a
this.b=b
this.c=c},
N:function N(a,b){this.a=a
this.b=b},
Q:function Q(a,b){this.a=a
this.b=b},
cY:function cY(a,b,c){this.a=a
this.c=b
this.x=c},
cU:function cU(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
fe(a,b){return new A.cW(a,b)},
ff(a,b){return new A.ca(a,b)},
db:function db(){},
cW:function cW(a,b){this.b=a
this.a=b},
ca:function ca(a,b){this.b=a
this.a=b},
cZ:function cZ(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.e=d},
aG:function aG(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
jo(a){var s={}
s.a=null
A.H(v.G.self).onmessage=A.cP(new A.ey(s,a))},
io(a){var s,r,q,p,o,n,m,l,k,j,i,h=null
if(a==null||!t.m.b(a))return h
A.H(a)
s=t.dE.a(a.h)
if(s==null)return h
r=null
try{q=s
p=q.byteLength
if(p<12)A.ad(A.eC("spawn envelope: need at least 12 bytes, got "+p))
o=A.fc(q,0,12)
n=o.getUint8(0)
if(n!==1)A.ad(A.eC("spawn envelope: unsupported version "+n+" (expected 1)"))
m=o.getUint8(1)
l=A.hP(m)
if(l==null)A.ad(A.eC("spawn envelope: unknown kind "+m))
r=new A.cD(n,l,o.getUint16(2,!0),o.getUint32(4,!0),o.getUint32(8,!0))}catch(k){if(A.D(k) instanceof A.cg)return h
else throw k}j=a.p
if(j==null)i=h
else i=r.c!==0||r.b===B.l||r.b===B.m||r.b===B.h?t.Y.a(j):A.eQ(j)
return new A.J(r.b,r.c,r.d,i,h)},
iW(a,b){var s,r,q=t.c.a(new v.G.Array()),p=new A.ej(A.z([],t.f),q)
for(s=b.length,r=0;r<b.length;b.length===s||(0,A.an)(b),++r)p.$1(b[r])
return q},
eX(a,b){var s,r,q,p
if(a==null)return null
if(a instanceof A.aV){s={}
r=a.a
s.$spawn$platform=r
if(r!=null&&A.fQ(r)!=="SharedArrayBuffer")B.a.j(b,r)
return s}if(A.cQ(a))return a
if(A.eT(a))return a
if(typeof a=="number")return a
if(typeof a=="string")return a
if(t.J.b(a))return t.a.a(a)
if(t.p.b(a))return a
if(t.U.b(a))return a
if(t.go.b(a))return a
if(t.dQ.b(a))return a
if(t.h7.b(a))return a
if(t.an.b(a))return a
if(t.bv.b(a))return a
if(t.h4.b(a))return a
if(t.q.b(a))return a
if(t.V.b(a))return a
if(t.j.b(a)){q=t.c.a(new v.G.Array())
for(p=0;p<a.length;++p)q[p]=A.eX(a[p],b)
return q}if(t.G.b(a)){s={}
a.J(0,new A.ei(s,b))
return s}throw A.b(A.aE(a,"message","spawn cannot carry this value"))},
eQ(a){var s,r,q,p
if(a==null)return null
if(typeof a==="boolean")return A.eO(a)
if(typeof a==="string")return A.a1(a)
if(typeof a==="number"){A.ec(a)
if(isFinite(a))s=a===(a<0?Math.ceil(a):Math.floor(a))
else s=!1
if(s)return B.j.bc(a)
return a}if(!(typeof a==="object"))return null
switch(A.fQ(a)){case"ArrayBuffer":return t.a.a(a)
case"Uint8Array":return t.Y.a(a)
case"Int8Array":return t.cv.a(a)
case"Uint8ClampedArray":return t.gi.a(a)
case"Int16Array":return t.at.a(a)
case"Uint16Array":return t.d.a(a)
case"Int32Array":return t.ha.a(a)
case"Uint32Array":return t.dk.a(a)
case"Float32Array":return t.al.a(a)
case"Float64Array":return t.c2.a(a)
case"DataView":return t.gT.a(a)
case"Array":t.c.a(a)
r=A.G(A.ec(a.length))
s=[]
for(q=0;q<r;++q)s.push(A.eQ(a[q]))
return s
default:A.H(a)
if("$spawn$platform" in a)return new A.aV(a.$spawn$platform)
p=t.c.a(v.G.Object.keys(a))
r=A.G(A.ec(p.length))
s=A.eF(t.N,t.X)
for(q=0;q<r;++q)s.E(0,A.a1(p[q]),A.eQ(a[A.a1(p[q])]))
return s}},
fQ(a){var s,r=A.fN(A.H(a).constructor)
if(r==null)s=null
else{s=A.ed(r.name)
if(s==null)s=null}return s},
ey:function ey(a,b){this.a=a
this.b=b},
ex:function ex(){},
cN:function cN(a,b){this.a=a
this.b=b},
ej:function ej(a,b){this.a=a
this.b=b},
ei:function ei(a,b){this.a=a
this.b=b},
ct:function ct(a,b){this.a=a
this.b=b},
cu:function cu(a,b){this.a=a
this.b=b},
df:function df(){},
cS(a,b,c,d){return A.jn(a,b,c,d)},
jn(a,b,c,a0){var s=0,r=A.W(t.H),q=1,p=[],o=[],n,m,l,k,j,i,h,g,f,e,d
var $async$cS=A.X(function(a1,a2){if(a1===1){p.push(a2)
s=q}for(;;)switch(s){case 0:f=t.X
e=new A.bY(a,A.fu(f),new A.a5(new A.e($.f,t.D),t.h),A.z([],t.b4),c)
a.G(new A.J(B.l,0,0,B.i.a7(B.M.bM(A.d7(["v",1,"caps",a0.bd()],t.N,f),null)),null))
f=a.a
n=new A.aY(f,A.o(f).h("aY<1>")).bU(e.gbv(),e.gbx())
q=3
f=b.$1(e)
s=6
return A.B(f instanceof A.e?f:A.dH(f,t.H),$async$cS)
case 6:o.push(5)
s=4
break
case 3:q=2
d=p.pop()
m=A.D(d)
l=A.I(d)
f=A.a6(m)
j=t.l.a(l)
i=e.a
h=J.ac(f)
g=A.C(h.gk(f).a,null)
f=h.i(f)
j=j.i(0)
i.G(new A.J(B.h,0,0,B.i.a7(g+"\n"+A.f4(f,"\n"," ")+"\n"+j),null))
o.push(5)
s=4
break
case 2:o=[1]
case 4:q=1
e.aj()
f=n
if(((f.e&=4294967279)&8)===0)f.aH()
f=f.f
s=7
return A.B(f==null?$.ez():f,$async$cS)
case 7:a.G(B.R)
s=o.pop()
break
case 5:return A.U(null,r)
case 1:return A.T(p.at(-1),r)}})
return A.V($async$cS,r)},
bY:function bY(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=null
_.f=!1
_.r=e},
e9:function e9(a,b){this.a=a
this.b=b},
ea:function ea(a,b){this.a=a
this.b=b},
eb:function eb(a,b){this.a=a
this.b=b},
J:function J(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
j9(a){A.eP(a,A.z([],t.f),"message")
return new A.bN(0,a)},
f0(a,b){if(a===0)return b
if(!t.p.b(b))throw A.b(A.a8("spawn: frame declares typeId "+a+" but carries "+J.b6(b).i(0)+" instead of bytes"))
return $.hq().bK(a,b)},
eP(a,b,c){var s,r,q,p
if(a==null||A.cQ(a)||typeof a=="number"||typeof a=="string"||t.ak.b(a)||t.J.b(a)||a instanceof A.aV)return
s=t.j.b(a)
if(s||t.G.b(a)){for(r=b.length,q=0;q<r;++q)if(b[q]===a)throw A.b(A.aE(a,c,"spawn cannot carry a cyclic structure"))
B.a.j(b,a)
if(s)for(s=c+"[",p=0;p<a.length;++p)A.eP(a[p],b,s+p+"]")
else if(t.G.b(a))a.J(0,new A.eg(c,b))
if(0>=b.length)return A.h(b,-1)
b.pop()
return}throw A.b(A.aE(a,c,"spawn cannot carry "+J.b6(a).i(0)+". Wrap a platform object (VideoFrame, AudioData, ImageBitmap, ...) in a PlatformValue. Portable values are null, bool, int, double, String, TypedData, ByteBuffer, and List/Map<String, ...> of those. Implement WireMessage for anything else."))},
eg:function eg(a,b){this.a=a
this.b=b},
aV:function aV(a){this.a=a},
hP(a){var s,r
for(s=0;s<6;++s){r=B.W[s]
if(r.c===a)return r}return null},
a4:function a4(a,b,c){this.c=a
this.a=b
this.b=c},
cD:function cD(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
dw:function dw(a){this.a=a},
fc(a,b,c){var s=a.BYTES_PER_ELEMENT
c=A.eH(b,c,B.c.aC(a.byteLength,s))
return J.ht(B.a1.gbJ(a),a.byteOffset+b*s,(c-b)*s)},
hd(a){return v.mangledGlobalNames[a]}},B={}
var w=[A,J,B]
var $={}
A.eD.prototype={}
J.ci.prototype={
D(a,b){return a===b},
gl(a){return A.bu(a)},
i(a){return"Instance of '"+A.cr(a)+"'"},
gk(a){return A.a2(A.eR(this))}}
J.ck.prototype={
i(a){return String(a)},
gl(a){return a?519018:218159},
gk(a){return A.a2(t.y)},
$ik:1,
$icR:1}
J.bg.prototype={
D(a,b){return null==b},
i(a){return"null"},
gl(a){return 0},
gk(a){return A.a2(t.P)},
$ik:1,
$it:1}
J.bi.prototype={$iq:1}
J.ag.prototype={
gl(a){return 0},
gk(a){return B.aa},
i(a){return String(a)}}
J.cq.prototype={}
J.bB.prototype={}
J.a7.prototype={
i(a){var s=a[$.hf()]
if(s==null)s=a[$.f5()]
if(s==null)return this.bh(a)
return"JavaScript function for "+J.aD(s)},
$iao:1}
J.aI.prototype={
gl(a){return 0},
i(a){return String(a)}}
J.aJ.prototype={
gl(a){return 0},
i(a){return String(a)}}
J.p.prototype={
j(a,b){A.bZ(a).c.a(b)
a.$flags&1&&A.ae(a,29)
a.push(b)},
b9(a,b){var s
a.$flags&1&&A.ae(a,"removeAt",1)
s=a.length
if(b>=s)throw A.b(A.fr(b,null))
return a.splice(b,1)[0]},
F(a){a.$flags&1&&A.ae(a,"clear","clear")
a.length=0},
gb6(a){return a.length!==0},
i(a){return A.fi(a,"[","]")},
gu(a){return new J.b7(a,a.length,A.bZ(a).h("b7<1>"))},
gl(a){return A.bu(a)},
gp(a){return a.length},
E(a,b,c){A.bZ(a).c.a(c)
a.$flags&2&&A.ae(a)
if(!(b>=0&&b<a.length))throw A.b(A.h3(a,b))
a[b]=c},
gk(a){return A.a2(A.bZ(a))},
$ii:1,
$id:1,
$im:1}
J.cj.prototype={
c0(a){var s,r,q
if(!Array.isArray(a))return null
s=a.$flags|0
if((s&4)!==0)r="const, "
else if((s&2)!==0)r="unmodifiable, "
else r=(s&1)!==0?"fixed, ":""
q="Instance of '"+A.cr(a)+"'"
if(r==="")return q
return q+" ("+r+"length: "+a.length+")"}}
J.d4.prototype={}
J.b7.prototype={
gq(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s,r=this,q=r.a,p=q.length
if(r.b!==p){q=A.an(q)
throw A.b(q)}s=r.c
if(s>=p){r.d=null
return!1}r.d=q[s]
r.c=s+1
return!0},
$iR:1}
J.bh.prototype={
bc(a){var s
if(a>=-2147483648&&a<=2147483647)return a|0
if(isFinite(a)){s=a<0?Math.ceil(a):Math.floor(a)
return s+0}throw A.b(A.bD(""+a+".toInt()"))},
i(a){if(a===0&&1/a<0)return"-0.0"
else return""+a},
gl(a){var s,r,q,p,o=a|0
if(a===o)return o&536870911
s=Math.abs(a)
r=Math.log(s)/0.6931471805599453|0
q=Math.pow(2,r)
p=s<1?s/q:q/s
return((p*9007199254740992|0)+(p*3542243181176521|0))*599197+r*1259&536870911},
aC(a,b){if((a|0)===a)if(b>=1||b<-1)return a/b|0
return this.aY(a,b)},
am(a,b){return(a|0)===a?a/b|0:this.aY(a,b)},
aY(a,b){var s=a/b
if(s>=-2147483648&&s<=2147483647)return s|0
if(s>0){if(s!==1/0)return Math.floor(s)}else if(s>-1/0)return Math.ceil(s)
throw A.b(A.bD("Result of truncating division is "+A.j(s)+": "+A.j(a)+" ~/ "+b))},
aW(a,b){var s
if(a>0)s=this.bF(a,b)
else{s=b>31?31:b
s=a>>s>>>0}return s},
bF(a,b){return b>31?0:a>>>b},
gk(a){return A.a2(t.o)},
$il:1,
$iaC:1}
J.bf.prototype={
gk(a){return A.a2(t.S)},
$ik:1,
$ia:1}
J.cl.prototype={
gk(a){return A.a2(t.i)},
$ik:1}
J.aH.prototype={
V(a,b,c){return a.substring(b,A.eH(b,c,a.length))},
bg(a,b){var s,r
if(0>=b)return""
if(b===1||a.length===0)return a
if(b!==b>>>0)throw A.b(B.N)
for(s=a,r="";;){if((b&1)===1)r=s+r
b=b>>>1
if(b===0)break
s+=s}return r},
bW(a,b,c){var s=b-a.length
if(s<=0)return a
return this.bg(c,s)+a},
i(a){return a},
gl(a){var s,r,q
for(s=a.length,r=0,q=0;q<s;++q){r=r+a.charCodeAt(q)&536870911
r=r+((r&524287)<<10)&536870911
r^=r>>6}r=r+((r&67108863)<<3)&536870911
r^=r>>11
return r+((r&16383)<<15)&536870911},
gk(a){return A.a2(t.N)},
gp(a){return a.length},
$ik:1,
$ifn:1,
$iL:1}
A.aK.prototype={
i(a){return"LateInitializationError: "+this.a}}
A.eu.prototype={
$0(){var s=new A.e($.f,t.D)
s.L(null)
return s},
$S:10}
A.de.prototype={}
A.i.prototype={}
A.bn.prototype={
gq(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s,r=this,q=r.a,p=J.h4(q),o=p.gp(q)
if(r.b!==o)throw A.b(A.cc(q))
s=r.c
if(s>=o){r.d=null
return!1}r.d=p.b3(q,s);++r.c
return!0},
$iR:1}
A.as.prototype={
gu(a){var s=this.a
return new A.bp(s.gu(s),this.b,A.o(this).h("bp<1,2>"))},
gp(a){var s=this.a
return s.gp(s)}}
A.bc.prototype={$ii:1}
A.bp.prototype={
n(){var s=this,r=s.b
if(r.n()){s.a=s.c.$1(r.gq())
return!0}s.a=null
return!1},
gq(){var s=this.a
return s==null?this.$ti.y[1].a(s):s},
$iR:1}
A.E.prototype={}
A.bN.prototype={$r:"+(1,2)",$s:1}
A.b9.prototype={
gaz(a){return this.gp(this)===0},
i(a){return A.eG(this)},
ga8(){return new A.b0(this.bO(),A.o(this).h("b0<F<1,2>>"))},
bO(){var s=this
return function(){var r=0,q=1,p=[],o,n,m,l,k
return function $async$ga8(a,b,c){if(b===1){p.push(c)
r=q}for(;;)switch(r){case 0:o=s.gbT(),o=o.gu(o),n=A.o(s),m=n.y[1],n=n.h("F<1,2>")
case 2:if(!o.n()){r=3
break}l=o.gq()
k=s.m(0,l)
r=4
return a.b=new A.F(l,k==null?m.a(k):k,n),1
case 4:r=2
break
case 3:return 0
case 1:return a.c=p.at(-1),3}}}},
$iar:1}
A.ba.prototype={
gp(a){return this.b.length},
gaQ(){var s=this.$keys
if(s==null){s=Object.keys(this.a)
this.$keys=s}return s},
a6(a){if(typeof a!="string")return!1
if("__proto__"===a)return!1
return this.a.hasOwnProperty(a)},
m(a,b){if(!this.a6(b))return null
return this.b[this.a[b]]},
J(a,b){var s,r,q,p
this.$ti.h("~(1,2)").a(b)
s=this.gaQ()
r=this.b
for(q=s.length,p=0;p<q;++p)b.$2(s[p],r[p])},
gbT(){return new A.bH(this.gaQ(),this.$ti.h("bH<1>"))}}
A.bH.prototype={
gp(a){return this.a.length},
gu(a){var s=this.a
return new A.bI(s,s.length,this.$ti.h("bI<1>"))}}
A.bI.prototype={
gq(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s=this,r=s.c
if(r>=s.b){s.d=null
return!1}s.d=s.a[r]
s.c=r+1
return!0},
$iR:1}
A.bx.prototype={}
A.dj.prototype={
A(a){var s,r,q=this,p=new RegExp(q.a).exec(a)
if(p==null)return null
s=Object.create(null)
r=q.b
if(r!==-1)s.arguments=p[r+1]
r=q.c
if(r!==-1)s.argumentsExpr=p[r+1]
r=q.d
if(r!==-1)s.expr=p[r+1]
r=q.e
if(r!==-1)s.method=p[r+1]
r=q.f
if(r!==-1)s.receiver=p[r+1]
return s}}
A.bt.prototype={
i(a){return"Null check operator used on a null value"}}
A.cm.prototype={
i(a){var s,r=this,q="NoSuchMethodError: method not found: '",p=r.b
if(p==null)return"NoSuchMethodError: "+r.a
s=r.c
if(s==null)return q+p+"' ("+r.a+")"
return q+p+"' on '"+s+"' ("+r.a+")"}}
A.cz.prototype={
i(a){var s=this.a
return s.length===0?"Error":"Error: "+s}}
A.dd.prototype={
i(a){return"Throw of null ('"+(this.a===null?"null":"undefined")+"' from JavaScript)"}}
A.be.prototype={}
A.bO.prototype={
i(a){var s,r=this.b
if(r!=null)return r
r=this.a
s=r!==null&&typeof r==="object"?r.stack:null
return this.b=s==null?"":s},
$ia_:1}
A.af.prototype={
i(a){var s=this.constructor,r=s==null?null:s.name
return"Closure '"+A.he(r==null?"unknown":r)+"'"},
gk(a){var s=A.f_(this)
return A.a2(s==null?A.b4(this):s)},
$iao:1,
gc3(){return this},
$C:"$1",
$R:1,
$D:null}
A.c7.prototype={$C:"$0",$R:0}
A.c8.prototype={$C:"$2",$R:2}
A.cx.prototype={}
A.cv.prototype={
i(a){var s=this.$static_name
if(s==null)return"Closure of unknown static method"
return"Closure '"+A.he(s)+"'"}}
A.aF.prototype={
D(a,b){if(b==null)return!1
if(this===b)return!0
if(!(b instanceof A.aF))return!1
return this.$_target===b.$_target&&this.a===b.a},
gl(a){return(A.h8(this.a)^A.bu(this.$_target))>>>0},
i(a){return"Closure '"+this.$_name+"' of "+("Instance of '"+A.cr(this.a)+"'")}}
A.cs.prototype={
i(a){return"RuntimeError: "+this.a}}
A.ap.prototype={
gp(a){return this.a},
gaz(a){return this.a===0},
ga8(){return new A.bk(this,A.o(this).h("bk<1,2>"))},
a6(a){var s=this.b
if(s==null)return!1
return s[a]!=null},
m(a,b){var s,r,q,p,o=null
if(typeof b=="string"){s=this.b
if(s==null)return o
r=s[b]
q=r==null?o:r.b
return q}else if(typeof b=="number"&&(b&0x3fffffff)===b){p=this.c
if(p==null)return o
r=p[b]
q=r==null?o:r.b
return q}else return this.bS(b)},
bS(a){var s,r,q=this.d
if(q==null)return null
s=this.bs(q,a)
r=this.b5(s,a)
if(r<0)return null
return s[r].b},
E(a,b,c){var s,r,q,p,o,n,m=this,l=A.o(m)
l.c.a(b)
l.y[1].a(c)
if(typeof b=="string"){s=m.b
m.aD(s==null?m.b=m.af():s,b,c)}else if(typeof b=="number"&&(b&0x3fffffff)===b){r=m.c
m.aD(r==null?m.c=m.af():r,b,c)}else{q=m.d
if(q==null)q=m.d=m.af()
p=m.b4(b)
o=q[p]
if(o==null)q[p]=[m.ag(b,c)]
else{n=m.b5(o,b)
if(n>=0)o[n].b=c
else o.push(m.ag(b,c))}}},
J(a,b){var s,r,q=this
A.o(q).h("~(1,2)").a(b)
s=q.e
r=q.r
while(s!=null){b.$2(s.a,s.b)
if(r!==q.r)throw A.b(A.cc(q))
s=s.c}},
aD(a,b,c){var s,r=A.o(this)
r.c.a(b)
r.y[1].a(c)
s=a[b]
if(s==null)a[b]=this.ag(b,c)
else s.b=c},
ag(a,b){var s=this,r=A.o(s),q=new A.d6(r.c.a(a),r.y[1].a(b))
if(s.e==null)s.e=s.f=q
else s.f=s.f.c=q;++s.a
s.r=s.r+1&1073741823
return q},
b4(a){return J.P(a)&1073741823},
bs(a,b){return a[this.b4(b)]},
b5(a,b){var s,r
if(a==null)return-1
s=a.length
for(r=0;r<s;++r)if(J.eA(a[r].a,b))return r
return-1},
i(a){return A.eG(this)},
af(){var s=Object.create(null)
s["<non-identifier-key>"]=s
delete s["<non-identifier-key>"]
return s},
$ifk:1}
A.d6.prototype={}
A.bm.prototype={
gp(a){return this.a.a},
gu(a){var s=this.a
return new A.aq(s,s.r,s.e,this.$ti.h("aq<1>"))}}
A.aq.prototype={
gq(){return this.d},
n(){var s,r=this,q=r.a
if(r.b!==q.r)throw A.b(A.cc(q))
s=r.c
if(s==null){r.d=null
return!1}else{r.d=s.a
r.c=s.c
return!0}},
$iR:1}
A.bk.prototype={
gp(a){return this.a.a},
gu(a){var s=this.a
return new A.bl(s,s.r,s.e,this.$ti.h("bl<1,2>"))}}
A.bl.prototype={
gq(){var s=this.d
s.toString
return s},
n(){var s,r=this,q=r.a
if(r.b!==q.r)throw A.b(A.cc(q))
s=r.c
if(s==null){r.d=null
return!1}else{r.d=new A.F(s.a,s.b,r.$ti.h("F<1,2>"))
r.c=s.c
return!0}},
$iR:1}
A.ep.prototype={
$1(a){return this.a(a)},
$S:7}
A.eq.prototype={
$2(a,b){return this.a(a,b)},
$S:11}
A.er.prototype={
$1(a){return this.a(A.a1(a))},
$S:12}
A.az.prototype={
gk(a){return A.a2(this.aP())},
aP(){return A.jb(this.$r,this.aO())},
i(a){return this.b_(!1)},
b_(a){var s,r,q,p,o,n=this.bq(),m=this.aO(),l=(a?"Record ":"")+"("
for(s=n.length,r="",q=0;q<s;++q,r=", "){l+=r
p=n[q]
if(typeof p=="string")l=l+p+": "
if(!(q<m.length))return A.h(m,q)
o=m[q]
l=a?l+A.fp(o):l+A.j(o)}l+=")"
return l.charCodeAt(0)==0?l:l},
bq(){var s,r=this.$s
while($.e0.length<=r)B.a.j($.e0,null)
s=$.e0[r]
if(s==null){s=this.bn()
B.a.E($.e0,r,s)}return s},
bn(){var s,r,q,p=this.$r,o=p.indexOf("("),n=p.substring(1,o),m=p.substring(o),l=m==="()"?0:m.replace(/[^,]/g,"").length+1,k=A.z(new Array(l),t.f)
for(s=0;s<l;++s)k[s]=s
if(n!==""){r=n.split(",")
s=r.length
for(q=l;s>0;){--q;--s
B.a.E(k,q,r[s])}}k=A.d8(k,!1,t.K)
k.$flags=3
return k}}
A.b_.prototype={
aO(){return[this.a,this.b]},
D(a,b){if(b==null)return!1
return b instanceof A.b_&&this.$s===b.$s&&J.eA(this.a,b.a)&&J.eA(this.b,b.b)},
gl(a){return A.fm(this.$s,this.a,this.b,B.d,B.d)}}
A.dF.prototype={}
A.ah.prototype={
gk(a){return B.a3},
b0(a,b,c){var s=new DataView(a,b,c)
return s},
$ik:1,
$iah:1,
$ib8:1}
A.aL.prototype={$iaL:1}
A.bs.prototype={
gbJ(a){if(((a.$flags|0)&2)!==0)return new A.cM(a.buffer)
else return a.buffer},
$iu:1}
A.cM.prototype={
b0(a,b,c){var s=A.hI(this.a,b,c)
s.$flags=3
return s},
$ib8:1}
A.aM.prototype={
gk(a){return B.a4},
$ik:1,
$iaM:1,
$icV:1}
A.aS.prototype={
gp(a){return a.length},
$iK:1}
A.bq.prototype={$ii:1,$id:1,$im:1}
A.br.prototype={$ii:1,$id:1,$im:1}
A.aN.prototype={
gk(a){return B.a5},
$ik:1,
$iaN:1,
$id_:1}
A.aO.prototype={
gk(a){return B.a6},
$ik:1,
$iaO:1,
$id0:1}
A.aP.prototype={
gk(a){return B.a7},
$ik:1,
$iaP:1,
$id1:1}
A.aQ.prototype={
gk(a){return B.a8},
$ik:1,
$iaQ:1,
$id2:1}
A.aR.prototype={
gk(a){return B.a9},
$ik:1,
$iaR:1,
$id3:1}
A.aT.prototype={
gk(a){return B.ac},
$ik:1,
$iaT:1,
$idl:1}
A.aU.prototype={
gk(a){return B.ad},
$ik:1,
$iaU:1,
$idm:1}
A.at.prototype={
gk(a){return B.ae},
gp(a){return a.length},
$ik:1,
$iat:1,
$idn:1}
A.ai.prototype={
gk(a){return B.af},
gp(a){return a.length},
$ik:1,
$iai:1,
$ibA:1}
A.bJ.prototype={}
A.bK.prototype={}
A.bL.prototype={}
A.bM.prototype={}
A.Z.prototype={
h(a){return A.bX(v.typeUniverse,this,a)},
t(a){return A.fK(v.typeUniverse,this,a)}}
A.cJ.prototype={}
A.e5.prototype={
i(a){return A.C(this.a,null)}}
A.cI.prototype={
i(a){return this.a}}
A.bT.prototype={$ia9:1}
A.dB.prototype={
$1(a){var s=this.a,r=s.a
s.a=null
r.$0()},
$S:8}
A.dA.prototype={
$1(a){var s,r
this.a.a=t.M.a(a)
s=this.b
r=this.c
s.firstChild?s.removeChild(r):s.appendChild(r)},
$S:13}
A.dC.prototype={
$0(){this.a.$0()},
$S:2}
A.dD.prototype={
$0(){this.a.$0()},
$S:2}
A.e3.prototype={
bi(a,b){if(self.setTimeout!=null)this.b=self.setTimeout(A.c2(new A.e4(this,b),0),a)
else throw A.b(A.bD("`setTimeout()` not found."))},
ar(){if(self.setTimeout!=null){var s=this.b
if(s==null)return
self.clearTimeout(s)
this.b=null}else throw A.b(A.bD("Canceling a timer."))}}
A.e4.prototype={
$0(){this.a.b=null
this.b.$0()},
$S:0}
A.bE.prototype={
a5(a){var s,r=this,q=r.$ti
q.h("1/?").a(a)
if(a==null)a=q.c.a(a)
if(!r.b)r.a.L(a)
else{s=r.a
if(q.h("A<1>").b(a))s.aI(a)
else s.ac(a)}},
av(a,b){var s=this.a
if(this.b)s.H(new A.x(a,b))
else s.M(new A.x(a,b))},
$icX:1}
A.ee.prototype={
$1(a){return this.a.$2(0,a)},
$S:4}
A.ef.prototype={
$2(a,b){this.a.$2(1,new A.be(a,t.l.a(b)))},
$S:14}
A.ek.prototype={
$2(a,b){this.a(A.G(a),b)},
$S:15}
A.bS.prototype={
gq(){var s=this.b
return s==null?this.$ti.c.a(s):s},
bB(a,b){var s,r,q
a=A.G(a)
b=b
s=this.a
for(;;)try{r=s(this,a,b)
return r}catch(q){b=q
a=1}},
n(){var s,r,q,p,o=this,n=null,m=0
for(;;){s=o.d
if(s!=null)try{if(s.n()){o.b=s.gq()
return!0}else o.d=null}catch(r){n=r
m=1
o.d=null}q=o.bB(m,n)
if(1===q)return!0
if(0===q){o.b=null
p=o.e
if(p==null||p.length===0){o.a=A.fE
return!1}if(0>=p.length)return A.h(p,-1)
o.a=p.pop()
m=0
n=null
continue}if(2===q){m=0
n=null
continue}if(3===q){n=o.c
o.c=null
p=o.e
if(p==null||p.length===0){o.b=null
o.a=A.fE
throw n
return!1}if(0>=p.length)return A.h(p,-1)
o.a=p.pop()
m=1
continue}throw A.b(A.a8("sync*"))}return!1},
c5(a){var s,r,q=this
if(a instanceof A.b0){s=a.a()
r=q.e
if(r==null)r=q.e=[]
B.a.j(r,q.a)
q.a=s
return 2}else{q.d=J.eB(a)
return 2}},
$iR:1}
A.b0.prototype={
gu(a){return new A.bS(this.a(),this.$ti.h("bS<1>"))}}
A.x.prototype={
i(a){return A.j(this.a)},
$in:1,
gK(){return this.b}}
A.bG.prototype={
av(a,b){var s=this.a
if((s.a&30)!==0)throw A.b(A.a8("Future already completed"))
s.M(A.iy(a,b))},
b2(a){return this.av(a,null)},
$icX:1}
A.a5.prototype={
a5(a){var s,r=this.$ti
r.h("1/?").a(a)
s=this.a
if((s.a&30)!==0)throw A.b(A.a8("Future already completed"))
s.L(r.h("1/").a(a))},
au(){return this.a5(null)}}
A.ab.prototype={
bV(a){var s
if((this.c&15)!==6)return!0
s=this.b.b
return s.a0(s,t.bN.a(this.d),a.a,t.y,t.K)},
bQ(a){var s,r=this,q=r.e,p=null,o=t.z,n=t.K,m=a.a,l=r.b.b
if(t.Q.b(q))p=l.bC(l,q,m,a.b,o,n,t.l)
else p=l.a0(l,t.v.a(q),m,o,n)
try{o=r.$ti.h("2/").a(p)
return o}catch(s){if(t.eK.b(A.D(s))){if((r.c&1)!==0)throw A.b(A.c3("The error handler of Future.then must return a value of the returned future's type","onError"))
throw A.b(A.c3("The error handler of Future.catchError must return a value of the future's type","onError"))}else throw s}}}
A.e.prototype={
U(a,b,c){var s,r,q,p=this.$ti
p.t(c).h("1/(2)").a(a)
s=$.f
if(s===B.b){if(b!=null&&!t.Q.b(b)&&!t.v.b(b))throw A.b(A.aE(b,"onError",u.c))}else{r=p.c
a=s.Z(s,c.h("@<0/>").t(r).h("1(2)").a(a),c.h("0/"),r)
if(b!=null)b=A.iO(b,s)}q=new A.e(s,c.h("e<0>"))
r=b==null?1:3
this.W(new A.ab(q,r,a,b,p.h("@<1>").t(c).h("ab<1,2>")))
return q},
c_(a,b){return this.U(a,null,b)},
aZ(a,b,c){var s,r=this.$ti
r.t(c).h("1/(2)").a(a)
s=new A.e($.f,c.h("e<0>"))
this.W(new A.ab(s,19,a,b,r.h("@<1>").t(c).h("ab<1,2>")))
return s},
aA(a){var s,r,q
t.O.a(a)
s=this.$ti
r=$.f
q=new A.e(r,s)
if(r!==B.b)a=r.I(r,a,t.z)
this.W(new A.ab(q,8,a,null,s.h("ab<1,1>")))
return q},
bD(a){this.a=this.a&1|16
this.c=a},
Y(a){this.a=a.a&30|this.a&1
this.c=a.c},
W(a){var s,r=this,q=r.a
if(q<=3){a.a=t.F.a(r.c)
r.c=a}else{if((q&4)!==0){s=t._.a(r.c)
if((s.a&24)===0){s.W(a)
return}r.Y(s)}q=r.b
q.S(q,new A.dI(r,a))}},
aV(a){var s,r,q,p,o,n,m=this,l={}
l.a=a
if(a==null)return
s=m.a
if(s<=3){r=t.F.a(m.c)
m.c=a
if(r!=null){q=a.a
for(p=a;q!=null;p=q,q=o)o=q.a
p.a=r}}else{if((s&4)!==0){n=t._.a(m.c)
if((n.a&24)===0){n.aV(a)
return}m.Y(n)}l.a=m.a_(a)
s=m.b
s.S(s,new A.dN(l,m))}},
P(){var s=t.F.a(this.c)
this.c=null
return this.a_(s)},
a_(a){var s,r,q
for(s=a,r=null;s!=null;r=s,s=q){q=s.a
s.a=r}return r},
aK(a){var s,r=this,q=r.$ti
q.h("1/").a(a)
if(q.h("A<1>").b(a))A.dL(a,r,!0)
else{s=r.P()
q.c.a(a)
r.a=8
r.c=a
A.ax(r,s)}},
ac(a){var s,r=this
r.$ti.c.a(a)
s=r.P()
r.a=8
r.c=a
A.ax(r,s)},
bm(a){var s=this.P()
this.Y(a)
A.ax(this,s)},
H(a){var s=this.P()
this.bD(a)
A.ax(this,s)},
bl(a,b){A.a6(a)
t.l.a(b)
this.H(new A.x(a,b))},
L(a){var s=this.$ti
s.h("1/").a(a)
if(s.h("A<1>").b(a)){this.aI(a)
return}this.bj(a)},
bj(a){var s,r=this
r.$ti.c.a(a)
r.a^=2
s=r.b
s.S(s,new A.dK(r,a))},
aI(a){A.dL(this.$ti.h("A<1>").a(a),this,!1)
return},
M(a){var s
this.a^=2
s=this.b
s.S(s,new A.dJ(this,a))},
bb(a,b){var s,r,q=this,p={},o=q.$ti
o.h("1/()?").a(b)
if((q.a&24)!==0){p=new A.e($.f,o)
p.L(q)
return p}s=$.f
r=new A.e(s,o)
p.a=null
p.a=A.hO(a,new A.dT(q,r,s,s.I(s,o.h("1/()").a(b),o.h("1/"))))
q.U(new A.dU(p,q,r),new A.dV(p,r),t.P)
return r},
$iA:1}
A.dI.prototype={
$0(){A.ax(this.a,this.b)},
$S:0}
A.dN.prototype={
$0(){A.ax(this.b,this.a.a)},
$S:0}
A.dM.prototype={
$0(){A.dL(this.a.a,this.b,!0)},
$S:0}
A.dK.prototype={
$0(){this.a.ac(this.b)},
$S:0}
A.dJ.prototype={
$0(){this.a.H(this.b)},
$S:0}
A.dQ.prototype={
$0(){var s,r,q,p,o,n,m,l,k=this,j=null
try{q=k.a.a
p=q.b.b
j=p.R(p,t.O.a(q.d),t.z)}catch(o){s=A.D(o)
r=A.I(o)
if(k.c&&t.n.a(k.b.a.c).a===s){q=k.a
q.c=t.n.a(k.b.a.c)}else{q=s
p=r
if(p==null)p=A.c6(q)
n=k.a
n.c=new A.x(q,p)
q=n}q.b=!0
return}if(j instanceof A.e&&(j.a&24)!==0){if((j.a&16)!==0){q=k.a
q.c=t.n.a(j.c)
q.b=!0}return}if(j instanceof A.e){m=k.b.a
l=new A.e(m.b,m.$ti)
j.U(new A.dR(l,m),new A.dS(l),t.H)
q=k.a
q.c=l
q.b=!1}},
$S:0}
A.dR.prototype={
$1(a){this.a.bm(this.b)},
$S:8}
A.dS.prototype={
$2(a,b){A.a6(a)
t.l.a(b)
this.a.H(new A.x(a,b))},
$S:5}
A.dP.prototype={
$0(){var s,r,q,p,o,n,m,l,k
try{q=this.a
p=q.a
o=p.$ti
n=o.c
m=n.a(this.b)
l=p.b.b
q.c=l.a0(l,o.h("2/(1)").a(p.d),m,o.h("2/"),n)}catch(k){s=A.D(k)
r=A.I(k)
q=s
p=r
if(p==null)p=A.c6(q)
o=this.a
o.c=new A.x(q,p)
o.b=!0}},
$S:0}
A.dO.prototype={
$0(){var s,r,q,p,o,n,m,l=this
try{s=t.n.a(l.a.a.c)
p=l.b
if(p.a.bV(s)&&p.a.e!=null){p.c=p.a.bQ(s)
p.b=!1}}catch(o){r=A.D(o)
q=A.I(o)
p=t.n.a(l.a.a.c)
if(p.a===r){n=l.b
n.c=p
p=n}else{p=r
n=q
if(n==null)n=A.c6(p)
m=l.b
m.c=new A.x(p,n)
p=m}p.b=!0}},
$S:0}
A.dT.prototype={
$0(){var s,r,q,p,o,n=this
try{q=n.c
p=n.a.$ti
n.b.aK(q.R(q,p.h("1/()").a(n.d),p.h("1/")))}catch(o){s=A.D(o)
r=A.I(o)
q=s
p=r
if(p==null)p=A.c6(q)
n.b.H(new A.x(q,p))}},
$S:0}
A.dU.prototype={
$1(a){var s
this.b.$ti.c.a(a)
s=this.a.a
if(s.b!=null){s.ar()
this.c.ac(a)}},
$S(){return this.b.$ti.h("t(1)")}}
A.dV.prototype={
$2(a,b){var s
A.a6(a)
t.l.a(b)
s=this.a.a
if(s.b!=null){s.ar()
this.b.H(new A.x(a,b))}},
$S:5}
A.cE.prototype={}
A.bz.prototype={
gp(a){var s={},r=new A.e($.f,t.fJ)
s.a=0
this.b7(new A.dg(s,this),!0,new A.dh(s,r),r.gbk())
return r}}
A.dg.prototype={
$1(a){this.b.$ti.c.a(a);++this.a.a},
$S(){return this.b.$ti.h("~(1)")}}
A.dh.prototype={
$0(){this.b.aK(this.a.a)},
$S:0}
A.bP.prototype={
gbz(){var s,r=this
if((r.b&8)===0)return A.o(r).h("a0<1>?").a(r.a)
s=A.o(r)
return s.h("a0<1>?").a(s.h("bQ<1>").a(r.a).gan())},
aN(){var s,r,q=this
if((q.b&8)===0){s=q.a
if(s==null)s=q.a=new A.a0(A.o(q).h("a0<1>"))
return A.o(q).h("a0<1>").a(s)}r=A.o(q)
s=r.h("bQ<1>").a(q.a).gan()
return r.h("a0<1>").a(s)},
gaX(){var s=this.a
if((this.b&8)!==0)s=t.fv.a(s).gan()
return A.o(this).h("aZ<1>").a(s)},
aG(){if((this.b&4)!==0)return new A.au("Cannot add event after closing")
return new A.au("Cannot add event while adding a stream")},
aM(){var s=this.c
if(s==null)s=this.c=(this.b&2)!==0?$.ez():new A.e($.f,t.D)
return s},
j(a,b){var s,r=this,q=A.o(r)
q.c.a(b)
s=r.b
if(s>=4)throw A.b(r.aG())
if((s&1)!==0)r.ak(b)
else if((s&3)===0)r.aN().j(0,new A.av(b,q.h("av<1>")))},
v(){var s=this,r=s.b
if((r&4)!==0)return s.aM()
if(r>=4)throw A.b(s.aG())
r=s.b=r|4
if((r&1)!==0)s.al()
else if((r&3)===0)s.aN().j(0,B.v)
return s.aM()},
bG(a,b,c,d){var s,r,q,p,o,n,m,l,k,j=this,i=A.o(j)
i.h("~(1)?").a(a)
t.b.a(c)
if((j.b&3)!==0)throw A.b(A.a8("Stream has already been listened to."))
s=i.c
r=$.f
q=d?1:0
p=b!=null?32:0
o=t.H
s=r.Z(r,t.r.t(s).h("1(2)").a(a),o,s)
A.hV(r,b)
n=t.M
m=new A.aZ(j,s,r.I(r,n.a(c),o),r,q|p,i.h("aZ<1>"))
l=j.gbz()
if(((j.b|=1)&8)!==0){k=i.h("bQ<1>").a(j.a)
k.san(m)
k.bX()}else j.a=m
m.bE(l)
i=n.a(new A.e2(j))
s=m.e
m.e=s|64
i.$0()
m.e&=4294967231
m.aJ((s&4)!==0)
return m},
bA(a){var s,r,q,p,o,n,m,l,k=this,j=A.o(k)
j.h("cw<1>").a(a)
s=null
if((k.b&8)!==0)s=j.h("bQ<1>").a(k.a).ar()
k.a=null
k.b=k.b&4294967286|2
r=k.r
if(r!=null)if(s==null)try{q=r.$0()
if(q instanceof A.e)s=q}catch(n){p=A.D(n)
o=A.I(n)
m=new A.e($.f,t.D)
j=A.a6(p)
l=t.l.a(o)
m.M(new A.x(j,l))
s=m}else s=s.aA(r)
j=new A.e1(k)
if(s!=null)s=s.aA(j)
else j.$0()
return s},
$ift:1,
$ifD:1,
$iaw:1}
A.e2.prototype={
$0(){A.eV(this.a.d)},
$S:0}
A.e1.prototype={
$0(){var s=this.a.c
if(s!=null&&(s.a&30)===0)s.L(null)},
$S:0}
A.cF.prototype={
ak(a){var s=this.$ti
s.c.a(a)
this.gaX().aE(new A.av(a,s.h("av<1>")))},
al(){this.gaX().aE(B.v)}}
A.aX.prototype={}
A.aY.prototype={
gl(a){return(A.bu(this.a)^892482866)>>>0},
D(a,b){if(b==null)return!1
if(this===b)return!0
return b instanceof A.aY&&b.a===this.a}}
A.aZ.prototype={
aR(){return this.w.bA(this)},
aS(){var s=this.w,r=A.o(s)
r.h("cw<1>").a(this)
if((s.b&8)!==0)r.h("bQ<1>").a(s.a).c8()
A.eV(s.e)},
aT(){var s=this.w,r=A.o(s)
r.h("cw<1>").a(this)
if((s.b&8)!==0)r.h("bQ<1>").a(s.a).bX()
A.eV(s.f)}}
A.bF.prototype={
bE(a){var s=this
A.o(s).h("a0<1>?").a(a)
if(a==null)return
s.r=a
if(a.c!=null){s.e|=128
a.aa(s)}},
aH(){var s,r=this,q=r.e|=8
if((q&128)!==0){s=r.r
if(s.a===1)s.a=3}if((q&64)===0)r.r=null
r.f=r.aR()},
aS(){},
aT(){},
aR(){return null},
aE(a){var s,r=this,q=r.r
if(q==null)q=r.r=new A.a0(A.o(r).h("a0<1>"))
q.j(0,a)
s=r.e
if((s&128)===0){s|=128
r.e=s
if(s<256)q.aa(r)}},
ak(a){var s,r=this,q=A.o(r).c
q.a(a)
s=r.e
r.e=s|64
r.d.bZ(r.a,a,q)
r.e&=4294967231
r.aJ((s&4)!==0)},
al(){var s,r=this,q=new A.dE(r)
r.aH()
r.e|=16
s=r.f
if(s!=null&&s!==$.ez())s.aA(q)
else q.$0()},
aJ(a){var s,r,q=this,p=q.e
if((p&128)!==0&&q.r.c==null){p=q.e=p&4294967167
s=!1
if((p&4)!==0)if(p<256){s=q.r
s=s==null?null:s.c==null
s=s!==!1}if(s){p&=4294967291
q.e=p}}for(;;a=r){if((p&8)!==0){q.r=null
return}r=(p&4)!==0
if(a===r)break
q.e=p^64
if(r)q.aS()
else q.aT()
p=q.e&=4294967231}if((p&128)!==0&&p<256)q.r.aa(q)},
$icw:1,
$iaw:1}
A.dE.prototype={
$0(){var s=this.a,r=s.e
if((r&16)===0)return
s.e=r|74
s.d.ba(s.c)
s.e&=4294967231},
$S:0}
A.bR.prototype={
b7(a,b,c,d){var s=this.$ti
s.h("~(1)?").a(a)
t.b.a(c)
return this.a.bG(s.h("~(1)?").a(a),d,c,b===!0)},
bU(a,b){return this.b7(a,null,b,null)}}
A.aj.prototype={
sT(a){this.a=t.ev.a(a)},
gT(){return this.a}}
A.av.prototype={
b8(a){this.$ti.h("aw<1>").a(a).ak(this.b)}}
A.cG.prototype={
b8(a){a.al()},
gT(){return null},
sT(a){throw A.b(A.a8("No events after a done."))},
$iaj:1}
A.a0.prototype={
aa(a){var s,r=this
r.$ti.h("aw<1>").a(a)
s=r.a
if(s===1)return
if(s>=1){r.a=1
return}A.jp(new A.e_(r,a))
r.a=1},
j(a,b){var s=this,r=s.c
if(r==null)s.b=s.c=b
else{r.sT(b)
s.c=b}}}
A.e_.prototype={
$0(){var s,r,q,p=this.a,o=p.a
p.a=0
if(o===3)return
s=p.$ti.h("aw<1>").a(this.b)
r=p.b
q=r.gT()
p.b=q
if(q==null)p.c=null
r.b8(s)},
$S:0}
A.cK.prototype={}
A.dx.prototype={
bY(a,b){return this.R(this,b.h("0()").a(a),b)},
ba(a){var s,r,q,p,o=this
t.M.a(a)
try{q=o.R(o,a,t.H)
return q}catch(p){s=A.D(p)
r=A.I(p)
o.O(o,s,r)}},
bZ(a,b,c){var s,r,q,p,o=this
c.h("~(0)").a(a)
c.a(b)
try{q=o.a0(o,a,b,t.H,c)
return q}catch(p){s=A.D(p)
r=A.I(p)
o.O(o,s,r)}},
b1(a,b){return new A.dz(this,this.I(this,b.h("0()").a(a),b),b)},
bI(a){return new A.dy(this,this.I(this,t.M.a(a),t.H))},
O(a,b,c){var s,r,q,p,o,n,m,l
t.l.a(c)
s=null
if(s==null){A.iP(b,c)
return}r=s.gaB()
q=r.gc4()
p=$.f
try{$.f=q
s.bP(r,r.gah(),a,b,c)
$.f=p}catch(m){o=A.D(m)
n=A.I(m)
$.f=p
l=b===o?c:n
q.O(r,o,l)}},
R(a,b,c){var s,r,q
c.h("0()").a(b)
r=$.f
if(r===a)return b.$0()
s=r
$.f=a
try{r=b.$0()
return r}finally{$.f=s}q=null.gaB()
return null.c6(q,q.gah(),a,b)},
a0(a,b,c,d,e){var s,r,q
d.h("@<0>").t(e).h("1(2)").a(b)
e.a(c)
r=$.f
if(r===a)return b.$1(c)
s=r
$.f=a
try{r=b.$1(c)
return r}finally{$.f=s}q=null.gaB()
return null.bP(q,q.gah(),a,b,c)},
bC(a,b,c,d,e,f,g){var s,r,q
e.h("@<0>").t(f).t(g).h("1(2,3)").a(b)
f.a(c)
g.a(d)
r=$.f
if(r===a)return b.$2(c,d)
s=r
$.f=a
try{r=b.$2(c,d)
return r}finally{$.f=s}q=null.gaB()
return null.c7(q,q.gah(),a,b,c,d)},
I(a,b,c){c.h("0()").a(b)
return b},
Z(a,b,c,d){c.h("@<0>").t(d).h("1(2)").a(b)
return b},
ai(a,b,c,d,e){c.h("@<0>").t(d).t(e).h("1(2,3)").a(b)
return b},
bo(a,b,c){return null},
S(a,b){A.eU(a,t.M.a(b))
return},
aL(a,b,c){t.M.a(c)
return A.fw(b,B.b!==a?a.b1(c,t.H):c)}}
A.dz.prototype={
$0(){var s=this.a
return s.R(s,this.b,this.c)},
$S(){return this.c.h("0()")}}
A.dy.prototype={
$0(){return this.a.ba(this.b)},
$S:0}
A.eh.prototype={
$0(){A.hD(this.a,this.b)},
$S:0}
A.r.prototype={
gu(a){return new A.bn(a,a.length,A.b4(a).h("bn<r.E>"))},
b3(a,b){if(!(b<a.length))return A.h(a,b)
return a[b]},
gb6(a){return a.length!==0},
i(a){return A.fi(a,"[","]")}}
A.bo.prototype={
J(a,b){var s,r,q,p=this,o=A.o(p)
o.h("~(1,2)").a(b)
for(s=new A.aq(p,p.r,p.e,o.h("aq<1>")),o=o.y[1];s.n();){r=s.d
q=p.m(0,r)
b.$2(r,q==null?o.a(q):q)}},
ga8(){var s=A.o(this),r=s.h("bm<1>")
s=s.h("F<1,2>")
return A.hH(new A.bm(this,r),r.t(s).h("1(d.E)").a(new A.d9(this)),r.h("d.E"),s)},
gp(a){return this.a},
gaz(a){return this.a===0},
i(a){return A.eG(this)},
$iar:1}
A.d9.prototype={
$1(a){var s=this.a,r=A.o(s)
r.c.a(a)
s=s.m(0,a)
if(s==null)s=r.y[1].a(s)
return new A.F(a,s,r.h("F<1,2>"))},
$S(){return A.o(this.a).h("F<1,2>(1)")}}
A.da.prototype={
$2(a,b){var s,r=this.a
if(!r.a)this.b.a+=", "
r.a=!1
r=this.b
s=A.j(a)
r.a=(r.a+=s)+": "
s=A.j(b)
r.a+=s},
$S:3}
A.c9.prototype={}
A.cd.prototype={}
A.bj.prototype={
i(a){var s=A.cf(this.a)
return(this.b!=null?"Converting object to an encodable object failed:":"Converting object did not return an encodable object:")+" "+s}}
A.co.prototype={
i(a){return"Cyclic error in JSON stringify"}}
A.cn.prototype={
bM(a,b){var s=A.hY(a,this.gbN().b,null)
return s},
gbN(){return B.V}}
A.d5.prototype={}
A.dY.prototype={
bf(a){var s,r,q,p,o,n,m=a.length
for(s=this.c,r=0,q=0;q<m;++q){p=a.charCodeAt(q)
if(p>92){if(p>=55296){o=p&64512
if(o===55296){n=q+1
n=!(n<m&&(a.charCodeAt(n)&64512)===56320)}else n=!1
if(!n)if(o===56320){o=q-1
o=!(o>=0&&(a.charCodeAt(o)&64512)===55296)}else o=!1
else o=!0
if(o){if(q>r)s.a+=B.f.V(a,r,q)
r=q+1
o=A.y(92)
s.a+=o
o=A.y(117)
s.a+=o
o=A.y(100)
s.a+=o
o=p>>>8&15
o=A.y(o<10?48+o:87+o)
s.a+=o
o=p>>>4&15
o=A.y(o<10?48+o:87+o)
s.a+=o
o=p&15
o=A.y(o<10?48+o:87+o)
s.a+=o}}continue}if(p<32){if(q>r)s.a+=B.f.V(a,r,q)
r=q+1
o=A.y(92)
s.a+=o
switch(p){case 8:o=A.y(98)
s.a+=o
break
case 9:o=A.y(116)
s.a+=o
break
case 10:o=A.y(110)
s.a+=o
break
case 12:o=A.y(102)
s.a+=o
break
case 13:o=A.y(114)
s.a+=o
break
default:o=A.y(117)
s.a+=o
o=A.y(48)
s.a=(s.a+=o)+o
o=p>>>4&15
o=A.y(o<10?48+o:87+o)
s.a+=o
o=p&15
o=A.y(o<10?48+o:87+o)
s.a+=o
break}}else if(p===34||p===92){if(q>r)s.a+=B.f.V(a,r,q)
r=q+1
o=A.y(92)
s.a+=o
o=A.y(p)
s.a+=o}}if(r===0)s.a+=a
else if(r<m)s.a+=B.f.V(a,r,m)},
ab(a){var s,r,q,p
for(s=this.a,r=s.length,q=0;q<r;++q){p=s[q]
if(a==null?p==null:a===p)throw A.b(new A.co(a,null))}B.a.j(s,a)},
a9(a){var s,r,q,p,o=this
if(o.be(a))return
o.ab(a)
try{s=o.b.$1(a)
if(!o.be(s)){q=A.fj(a,null,o.gaU())
throw A.b(q)}q=o.a
if(0>=q.length)return A.h(q,-1)
q.pop()}catch(p){r=A.D(p)
q=A.fj(a,r,o.gaU())
throw A.b(q)}},
be(a){var s,r,q=this
if(typeof a=="number"){if(!isFinite(a))return!1
q.c.a+=B.j.i(a)
return!0}else if(a===!0){q.c.a+="true"
return!0}else if(a===!1){q.c.a+="false"
return!0}else if(a==null){q.c.a+="null"
return!0}else if(typeof a=="string"){s=q.c
s.a+='"'
q.bf(a)
s.a+='"'
return!0}else if(t.j.b(a)){q.ab(a)
q.c1(a)
s=q.a
if(0>=s.length)return A.h(s,-1)
s.pop()
return!0}else if(t.G.b(a)){q.ab(a)
r=q.c2(a)
s=q.a
if(0>=s.length)return A.h(s,-1)
s.pop()
return r}else return!1},
c1(a){var s,r=this.c
r.a+="["
if(J.hu(a)){if(0>=a.length)return A.h(a,0)
this.a9(a[0])
for(s=1;s<a.length;++s){r.a+=","
this.a9(a[s])}}r.a+="]"},
c2(a){var s,r,q,p,o,n,m=this,l={}
if(a.gaz(a)){m.c.a+="{}"
return!0}s=a.gp(a)*2
r=A.hG(s,null,t.X)
q=l.a=0
l.b=!0
a.J(0,new A.dZ(l,r))
if(!l.b)return!1
p=m.c
p.a+="{"
for(o='"';q<s;q+=2,o=',"'){p.a+=o
m.bf(A.a1(r[q]))
p.a+='":'
n=q+1
if(!(n<s))return A.h(r,n)
m.a9(r[n])}p.a+="}"
return!0}}
A.dZ.prototype={
$2(a,b){var s,r
if(typeof a!="string")this.a.b=!1
s=this.b
r=this.a
B.a.E(s,r.a++,a)
B.a.E(s,r.a++,b)},
$S:3}
A.dX.prototype={
gaU(){var s=this.c.a
return s.charCodeAt(0)==0?s:s}}
A.dp.prototype={
a7(a){var s,r,q,p,o=a.length,n=A.eH(0,null,o)
if(n===0)return new Uint8Array(0)
s=n*3
r=new Uint8Array(s)
q=new A.e7(r)
if(q.br(a,0,n)!==n){p=n-1
if(!(p>=0&&p<o))return A.h(a,p)
q.aq()}return new Uint8Array(r.subarray(0,A.im(0,q.b,s)))}}
A.e7.prototype={
aq(){var s,r=this,q=r.c,p=r.b,o=r.b=p+1
q.$flags&2&&A.ae(q)
s=q.length
if(!(p<s))return A.h(q,p)
q[p]=239
p=r.b=o+1
if(!(o<s))return A.h(q,o)
q[o]=191
r.b=p+1
if(!(p<s))return A.h(q,p)
q[p]=189},
bH(a,b){var s,r,q,p,o,n=this
if((b&64512)===56320){s=65536+((a&1023)<<10)|b&1023
r=n.c
q=n.b
p=n.b=q+1
r.$flags&2&&A.ae(r)
o=r.length
if(!(q<o))return A.h(r,q)
r[q]=s>>>18|240
q=n.b=p+1
if(!(p<o))return A.h(r,p)
r[p]=s>>>12&63|128
p=n.b=q+1
if(!(q<o))return A.h(r,q)
r[q]=s>>>6&63|128
n.b=p+1
if(!(p<o))return A.h(r,p)
r[p]=s&63|128
return!0}else{n.aq()
return!1}},
br(a,b,c){var s,r,q,p,o,n,m,l,k=this
if(b!==c){s=c-1
if(!(s>=0&&s<a.length))return A.h(a,s)
s=(a.charCodeAt(s)&64512)===55296}else s=!1
if(s)--c
for(s=k.c,r=s.$flags|0,q=s.length,p=a.length,o=b;o<c;++o){if(!(o<p))return A.h(a,o)
n=a.charCodeAt(o)
if(n<=127){m=k.b
if(m>=q)break
k.b=m+1
r&2&&A.ae(s)
s[m]=n}else{m=n&64512
if(m===55296){if(k.b+4>q)break
m=o+1
if(!(m<p))return A.h(a,m)
if(k.bH(n,a.charCodeAt(m)))o=m}else if(m===56320){if(k.b+3>q)break
k.aq()}else if(n<=2047){m=k.b
l=m+1
if(l>=q)break
k.b=l
r&2&&A.ae(s)
if(!(m<q))return A.h(s,m)
s[m]=n>>>6|192
k.b=l+1
s[l]=n&63|128}else{m=k.b
if(m+2>=q)break
l=k.b=m+1
r&2&&A.ae(s)
if(!(m<q))return A.h(s,m)
s[m]=n>>>12|224
m=k.b=l+1
if(!(l<q))return A.h(s,l)
s[l]=n>>>6&63|128
k.b=m+1
if(!(m<q))return A.h(s,m)
s[m]=n&63|128}}}return o}}
A.bb.prototype={
D(a,b){if(b==null)return!1
return b instanceof A.bb&&this.a===b.a},
gl(a){return B.c.gl(this.a)},
i(a){var s,r,q,p=this.a,o=p%36e8,n=B.c.am(o,6e7)
o%=6e7
s=n<10?"0":""
r=B.c.am(o,1e6)
q=r<10?"0":""
return""+(p/36e8|0)+":"+s+n+":"+q+r+"."+B.f.bW(B.c.i(o%1e6),6,"0")}}
A.cH.prototype={
i(a){return this.N()},
$ibd:1}
A.n.prototype={
gK(){return A.hJ(this)}}
A.c4.prototype={
i(a){var s=this.a
if(s!=null)return"Assertion failed: "+A.cf(s)
return"Assertion failed"}}
A.a9.prototype={}
A.a3.prototype={
gae(){return"Invalid argument"+(!this.a?"(s)":"")},
gad(){return""},
i(a){var s=this,r=s.c,q=r==null?"":" ("+r+")",p=s.d,o=p==null?"":": "+p,n=s.gae()+q+o
if(!s.a)return n
return n+s.gad()+": "+A.cf(s.gaw())},
gaw(){return this.b}}
A.bv.prototype={
gaw(){return A.fP(this.b)},
gae(){return"RangeError"},
gad(){var s,r=this.e,q=this.f
if(r==null)s=q!=null?": Not less than or equal to "+A.j(q):""
else if(q==null)s=": Not greater than or equal to "+A.j(r)
else if(q>r)s=": Not in inclusive range "+A.j(r)+".."+A.j(q)
else s=q<r?": Valid value range is empty":": Only valid value is "+A.j(r)
return s}}
A.ch.prototype={
gaw(){return A.G(this.b)},
gae(){return"RangeError"},
gad(){if(A.G(this.b)<0)return": index must not be negative"
var s=this.f
if(s===0)return": no indices are valid"
return": index should be less than "+s},
gp(a){return this.f}}
A.bC.prototype={
i(a){return"Unsupported operation: "+this.a}}
A.cy.prototype={
i(a){return"UnimplementedError: "+this.a}}
A.au.prototype={
i(a){return"Bad state: "+this.a}}
A.cb.prototype={
i(a){var s=this.a
if(s==null)return"Concurrent modification during iteration."
return"Concurrent modification during iteration: "+A.cf(s)+"."}}
A.cp.prototype={
i(a){return"Out of Memory"},
gK(){return null},
$in:1}
A.by.prototype={
i(a){return"Stack Overflow"},
gK(){return null},
$in:1}
A.dG.prototype={
i(a){return"Exception: "+this.a}}
A.cg.prototype={
i(a){var s=this.a,r=""!==s?"FormatException: "+s:"FormatException"
return r}}
A.d.prototype={
gp(a){var s,r=this.gu(this)
for(s=0;r.n();)++s
return s},
b3(a,b){var s,r
A.hK(b,"index")
s=this.gu(this)
for(r=b;s.n();){if(r===0)return s.gq();--r}throw A.b(A.fh(b,b-r,this,"index"))},
i(a){return A.hF(this,"(",")")}}
A.F.prototype={
i(a){return"MapEntry("+A.j(this.a)+": "+A.j(this.b)+")"}}
A.t.prototype={
gl(a){return A.c.prototype.gl.call(this,0)},
i(a){return"null"}}
A.c.prototype={$ic:1,
D(a,b){return this===b},
gl(a){return A.bu(this)},
i(a){return"Instance of '"+A.cr(this)+"'"},
gk(a){return A.h6(this)},
toString(){return this.i(this)}}
A.cL.prototype={
i(a){return""},
$ia_:1}
A.aW.prototype={
gp(a){return this.a.length},
i(a){var s=this.a
return s.charCodeAt(0)==0?s:s},
$ihN:1}
A.dc.prototype={
i(a){return"Promise was rejected with a value of `"+(this.a?"undefined":"null")+"`."}}
A.ev.prototype={
$1(a){return this.a.a5(this.b.h("0/?").a(a))},
$S:4}
A.ew.prototype={
$1(a){if(a==null)return this.a.b2(new A.dc(a===undefined))
return this.a.b2(a)},
$S:4}
A.cA.prototype={
ao(){var s=this.d
this.d=null
if(s!=null&&(s.a.a&30)===0)s.au()},
bt(a){var s,r,q,p,o,n,m,l
if(a==null||typeof a==="undefined")return
s=A.H(a)
try{r=A.G(s.numberOfFrames)
q=A.G(s.numberOfChannels)
p=A.G(s.sampleRate)
o={planeIndex:0,format:"f32"}
n=A.G(s.allocationSize(o))
l=n
if(typeof l!=="number")return l.aC()
l=B.j.am(l,4)
m=new Float32Array(l)
s.copyTo(m,o)
B.a.j(this.b,new A.aG(m,r,p,q,B.j.bc(A.fO(s.timestamp))))}finally{s.close()
this.ao()}},
X(){var s=0,r=A.W(t.H),q,p=this,o
var $async$X=A.X(function(a,b){if(a===1)return A.T(b,r)
for(;;)switch(s){case 0:if(p.b.length!==0||p.c!=null){s=1
break}o=new A.e($.f,t.D)
p.d=new A.a5(o,t.h)
s=3
return A.B(o.bb(B.w,new A.dq()),$async$X)
case 3:p.d=null
case 1:return A.U(q,r)}})
return A.V($async$X,r)},
a2(){var s=this.c
if(s!=null){this.c=null
throw A.b(A.ff("webcodecs",J.aD(s)))}},
B(a){var s=0,r=A.W(t.W),q,p=this,o,n,m,l
var $async$B=A.X(function(b,c){if(b===1)return A.T(c,r)
for(;;)switch(s){case 0:p.a2()
o=p.a
if(o==null)throw A.b(A.a8("WebCodecsAudioDecoder: not open"))
n=v.G.EncodedAudioChunk
m=a.e?"key":"delta"
o.decode(A.H(new n({type:m,timestamp:a.b,data:a.a})))
s=3
return A.B(p.X(),$async$B)
case 3:p.a2()
m=p.b
l=A.d8(m,!0,t.R)
B.a.F(m)
q=l
s=1
break
case 1:return A.U(q,r)}})
return A.V($async$B,r)},
C(){var s=0,r=A.W(t.W),q,p=this,o,n,m
var $async$C=A.X(function(a,b){if(a===1)return A.T(b,r)
for(;;)switch(s){case 0:m=p.a
if(m==null){q=B.X
s=1
break}s=3
return A.B(A.ha(A.H(m.flush()),t.X),$async$C)
case 3:p.a2()
o=p.b
n=A.d8(o,!0,t.R)
B.a.F(o)
q=n
s=1
break
case 1:return A.U(q,r)}})
return A.V($async$C,r)},
v(){var s=0,r=A.W(t.H),q=this,p,o
var $async$v=A.X(function(a,b){if(a===1)return A.T(b,r)
for(;;)switch(s){case 0:try{p=q.a
if(p!=null)p.close()}catch(n){}q.a=null
B.a.F(q.b)
q.ao()
return A.U(null,r)}})
return A.V($async$v,r)}}
A.dq.prototype={
$0(){},
$S:2}
A.dr.prototype={
$1(a){this.a.bt(a)},
$S:1}
A.ds.prototype={
$1(a){var s=this.a
s.c=a
s.ao()},
$S:1}
A.cB.prototype={
ap(){var s=this.d
this.d=null
if(s!=null&&(s.a.a&30)===0)s.au()},
bu(a){if(a==null||typeof a==="undefined")return
B.a.j(this.b,new A.cC(A.H(a)))
this.ap()},
a3(){var s=0,r=A.W(t.H),q,p=this,o
var $async$a3=A.X(function(a,b){if(a===1)return A.T(b,r)
for(;;)switch(s){case 0:if(p.b.length!==0||p.c!=null){s=1
break}o=new A.e($.f,t.D)
p.d=new A.a5(o,t.h)
s=3
return A.B(o.bb(B.w,new A.dt()),$async$a3)
case 3:p.d=null
case 1:return A.U(q,r)}})
return A.V($async$a3,r)},
a4(){var s=this.c
if(s!=null){this.c=null
throw A.b(A.ff("webcodecs",J.aD(s)))}},
B(a){var s=0,r=A.W(t.ca),q,p=this,o,n,m
var $async$B=A.X(function(b,c){if(b===1)return A.T(c,r)
for(;;)switch(s){case 0:p.a4()
o=p.a
if(o==null)throw A.b(A.a8("WebCodecsVideoDecoder: not open"))
n=v.G.EncodedVideoChunk
m=a.e?"key":"delta"
o.decode(A.H(new n({type:m,timestamp:a.b,data:a.a})))
n=p.b
if(n.length!==0){q=B.a.b9(n,0)
s=1
break}s=3
return A.B(p.a3(),$async$B)
case 3:p.a4()
q=n.length===0?null:B.a.b9(n,0)
s=1
break
case 1:return A.U(q,r)}})
return A.V($async$B,r)},
C(){var s=0,r=A.W(t.cW),q,p=this,o,n,m
var $async$C=A.X(function(a,b){if(a===1)return A.T(b,r)
for(;;)switch(s){case 0:m=p.a
if(m==null){q=B.Y
s=1
break}s=3
return A.B(A.ha(A.H(m.flush()),t.X),$async$C)
case 3:p.a4()
o=p.b
n=A.d8(o,!0,t.e)
B.a.F(o)
q=n
s=1
break
case 1:return A.U(q,r)}})
return A.V($async$C,r)},
v(){var s=0,r=A.W(t.H),q=this,p,o,n,m
var $async$v=A.X(function(a,b){if(a===1)return A.T(b,r)
for(;;)switch(s){case 0:try{p=q.a
if(p!=null)p.close()}catch(l){}q.a=null
for(p=q.b,n=p.length,m=0;m<p.length;p.length===n||(0,A.an)(p),++m)p[m].v()
B.a.F(p)
q.ap()
return A.U(null,r)}})
return A.V($async$v,r)}}
A.dt.prototype={
$0(){},
$S:2}
A.du.prototype={
$1(a){this.a.bu(a)},
$S:1}
A.dv.prototype={
$1(a){var s=this.a
s.c=a
s.ap()},
$S:1}
A.cC.prototype={
v(){if(this.b)return
this.b=!0
this.a.close()},
$ice:1}
A.el.prototype={
$1(a){var s=0,r=A.W(t.X),q,p=this,o,n,m,l,k,j,i,h,g,f,e
var $async$$1=A.X(function(b,c){if(b===1)return A.T(c,r)
for(;;)switch(s){case 0:s="open"===a?3:4
break
case 3:o=p.b
case 5:switch(o){case"video":s=7
break
case"audio":s=8
break
default:s=9
break}break
case 7:o=p.c
n=o.m(0,"codec")
n.toString
n=A.fg(B.Z,A.a1(n),t.cq)
m=t.E.a(o.m(0,"extra"))
A.cO(o.m(0,"width"))
A.cO(o.m(0,"height"))
e=p.a
s=10
return A.B(A.eK(new A.cY(n,m,A.fY(o))),$async$$1)
case 10:e.b=c
s=6
break
case 8:o=p.c
n=o.m(0,"codec")
n.toString
e=p.a
s=11
return A.B(A.eJ(new A.cU(A.fg(B.a_,A.a1(n),t.w),t.E.a(o.m(0,"extra")),A.cO(o.m(0,"sampleRate")),A.cO(o.m(0,"channels")),A.fY(o))),$async$$1)
case 11:e.a=c
s=6
break
case 9:throw A.b(A.fe("webcodecs-worker","unknown worker role: "+A.j(o)))
case 6:q=null
s=1
break
case 4:l=null
o=!1
if(t.j.b(a)){n=a.length
if(n===2){if(0>=n){q=A.h(a,0)
s=1
break}if("decode"===a[0]){if(1>=n){q=A.h(a,1)
s=1
break}k=a[1]
o=t.I
n=o.b(k)
if(n){o.a(k)
l=k}o=n}}}s=o?12:13
break
case 12:o=l.m(0,"data")
o.toString
t.p.a(o)
n=l.m(0,"pts")
n.toString
A.G(n)
m=l.m(0,"pts")
m.toString
A.G(m)
j=l.m(0,"key")
j.toString
i=new A.cZ(o,n,m,A.eO(j))
o=p.a
n=o.b
s=n!=null?14:15
break
case 14:e=A
s=16
return A.B(n.B(i),$async$$1)
case 16:q=e.h0(c)
s=1
break
case 15:n=[]
s=17
return A.B(o.a.B(i),$async$$1)
case 17:o=c,m=o.length,j=t.N,h=t.X,g=0
case 18:if(!(g<o.length)){s=20
break}f=o[g]
n.push(A.d7(["samples",f.a,"frames",f.b,"rate",f.c,"ch",f.d,"pts",f.e],j,h))
case 19:o.length===m||(0,A.an)(o),++g
s=18
break
case 20:q=n
s=1
break
case 13:s="flush"===a?21:22
break
case 21:o=p.a
n=o.b
s=n!=null?23:24
break
case 23:o=[]
s=25
return A.B(n.C(),$async$$1)
case 25:n=c,m=n.length,g=0
case 26:if(!(g<n.length)){s=28
break}o.push(A.h0(n[g]))
case 27:n.length===m||(0,A.an)(n),++g
s=26
break
case 28:q=o
s=1
break
case 24:n=[]
s=29
return A.B(o.a.C(),$async$$1)
case 29:o=c,m=o.length,j=t.N,h=t.X,g=0
case 30:if(!(g<o.length)){s=32
break}f=o[g]
n.push(A.d7(["samples",f.a,"frames",f.b,"rate",f.c,"ch",f.d,"pts",f.e],j,h))
case 31:o.length===m||(0,A.an)(o),++g
s=30
break
case 32:q=n
s=1
break
case 22:throw A.b(A.a8("unknown op: "+A.j(a)))
case 1:return A.U(q,r)}})
return A.V($async$$1,r)},
$S:16}
A.N.prototype={
N(){return"VideoCodec."+this.b}}
A.Q.prototype={
N(){return"AudioCodec."+this.b}}
A.cY.prototype={}
A.cU.prototype={}
A.db.prototype={
i(a){return A.h6(this).i(0)+": "+this.a}}
A.cW.prototype={
i(a){return"CodecInitException["+this.b+"]: "+this.a}}
A.ca.prototype={
i(a){return"CodecRuntimeException["+this.b+"]: "+this.a}}
A.cZ.prototype={
i(a){var s=this,r=s.e?"KEY":"P/B"
return"EncodedPacket("+s.a.length+"B, pts="+s.b+"us, dts="+s.c+"us, "+r+", track=0)"}}
A.aG.prototype={}
A.ey.prototype={
$1(a){var s,r,q,p,o,n=A.io(A.H(a).data)
if(n==null)return
r=this.a
q=r.a
if(q!=null){q.bL(n)
return}s=null
try{s=A.f0(n.b,n.d)}catch(p){s=null}o=new A.cN(A.fu(t.B),new A.a5(new A.e($.f,t.D),t.h))
r.a=o
A.cS(o,this.b,s,B.O).c_(new A.ex(),t.H)},
$S:17}
A.ex.prototype={
$1(a){A.H(v.G.self).close()},
$S:18}
A.cN.prototype={
G(a){var s,r,q={},p=a.d,o=t.p.b(p),n=o?p.byteLength:0,m=new Uint8Array(12),l=A.fc(m,0,null)
l.$flags&2&&A.ae(l,9)
l.setUint8(0,1)
l.setUint8(1,a.a.c)
l.setUint16(2,a.b,!0)
l.setUint32(4,a.c,!0)
l.setUint32(8,n,!0)
q.h=m
s=A.z([],t.f)
if(p!=null){p=o?p:A.eX(p,s)
q.p=p}r=A.iW(a.e,s)
A.H(v.G.self).postMessage(q,r)},
bL(a){var s=this.a,r=s.b
if((r&4)!==0)return
s.j(0,a)},
$ihQ:1}
A.ej.prototype={
$1(a){var s,r,q
for(s=this.a,r=s.length,q=0;q<r;++q)if(s[q]===a)return
B.a.j(s,a)
this.b[s.length-1]=a},
$S:19}
A.ei.prototype={
$2(a,b){this.a[A.j(a)]=A.eX(b,this.b)},
$S:3}
A.ct.prototype={
N(){return"SpawnHost."+this.b}}
A.cu.prototype={
N(){return"SpawnPayload."+this.b}}
A.df.prototype={
bd(){return A.d7(["hosted","dart","payload","js","zeroCopyTransfer",!0],t.N,t.X)},
i(a){return"SpawnCaps(hosted: dart, payload: js, zeroCopyTransfer: true)"}}
A.bY.prototype={
bR(a){var s,r,q
t.k.a(a)
this.e=a
s=this.d
if(s.length===0)return
r=A.fl(s,t.B)
B.a.F(s)
for(s=r.length,q=0;q<r.length;r.length===s||(0,A.an)(r),++q)this.aF(r[q],a)},
bw(a){var s,r,q=this
t.B.a(a)
switch(a.a.a){case 2:s=q.b
if((s.b&4)===0)s.j(0,A.f0(a.b,a.d))
break
case 3:r=q.e
if(r==null)B.a.j(q.d,a)
else q.aF(a,r)
break
case 1:q.aj()
break
case 0:case 4:case 5:break}},
aF(a,b){var s,r,q,p,o,n,m,l,k=this,j={}
t.k.a(b)
j.a=null
try{j.a=A.f0(a.b,a.d)}catch(n){s=A.D(n)
r=A.I(n)
k.a1(a.c,s,r)
return}q=A.hW()
try{m=q
j=A.hE(new A.e9(j,b),t.X)
l=m.b
if(l==null?m!=null:l!==m)A.ad(new A.aK("Local '' has already been initialized."))
m.b=j}catch(n){p=A.D(n)
o=A.I(n)
k.a1(a.c,p,o)
return}j=q
m=j.b
if(m==null?j==null:m===j)A.ad(new A.aK("Local '' has not been initialized."))
m.U(new A.ea(k,a),new A.eb(k,a),t.P)},
a1(a,b,c){var s,r,q
t.l.a(c)
s=J.ac(b)
r=A.C(s.gk(b).a,null)
s=s.i(b)
q=c.i(0)
this.a.G(new A.J(B.h,0,a,B.i.a7(r+"\n"+A.f4(s,"\n"," ")+"\n"+q),null))},
by(){return this.aj()},
aj(){var s,r=this
if(r.f)return
r.f=!0
s=r.c
if((s.a.a&30)===0)s.au()
r.bp()
s=r.b
if((s.b&4)===0)s.v()},
bp(){var s,r,q,p,o,n,m,l=this.d
if(l.length===0)return
s=A.fl(l,t.B)
B.a.F(l)
for(l=s.length,r=this.a,q=0;q<s.length;s.length===l||(0,A.an)(s),++q){p=s[q]
o=new A.au("spawn: the worker closed without installing a request handler (WorkerChannel.handleRequests was never called)")
n=A.C(o.gk(0).a,null)
o=o.i(0)
m=B.e.i(0)
r.G(new A.J(B.h,0,p.c,B.i.a7(n+"\n"+A.f4(o,"\n"," ")+"\n"+m),null))}},
$ieL:1}
A.e9.prototype={
$0(){return this.b.$1(this.a.a)},
$S:21}
A.ea.prototype={
$1(a){var s,r,q,p,o,n,m,l=this
try{s=null
r=null
q=null
p=A.j9(a)
r=p.a
q=p.b
l.a.a.G(new A.J(B.D,r,l.b.c,q,s))}catch(m){o=A.D(m)
n=A.I(m)
l.a.a1(l.b.c,o,n)}},
$S:1}
A.eb.prototype={
$2(a,b){this.a.a1(this.b.c,A.a6(a),t.l.a(b))},
$S:5}
A.J.prototype={
i(a){var s=this,r=s.a.i(0),q=s.d
return"Frame("+r+", typeId: "+s.b+", correlationId: "+s.c+", payload: "+A.j(t.p.b(q)?""+q.byteLength+" bytes":J.b6(q))+")"}}
A.eg.prototype={
$2(a,b){if(typeof a!="string")throw A.b(A.aE(a,this.a,"spawn map keys must be String, got "+J.b6(a).i(0)))
A.eP(b,this.b,this.a+'["'+a+'"]')},
$S:3}
A.aV.prototype={
i(a){return"PlatformValue("+J.b6(this.a).i(0)+")"}}
A.a4.prototype={
N(){return"WireKind."+this.b}}
A.cD.prototype={
i(a){var s=this
return"WireHeader(v"+s.a+", "+s.b.i(0)+", typeId: "+s.c+", correlationId: "+s.d+", payloadLength: "+s.e+")"},
D(a,b){var s=this
if(b==null)return!1
return b instanceof A.cD&&b.a===s.a&&b.b===s.b&&b.c===s.c&&b.d===s.d&&b.e===s.e},
gl(a){var s=this
return A.fm(s.a,s.b,s.c,s.d,s.e)}}
A.dw.prototype={
bK(a,b){var s
this.a.m(0,a)
s=A.a8("spawn: no WireMessage decoder registered for typeId "+a+". Both ends must call the same WireRegistry.instance.register(...).")
throw A.b(s)}};(function aliases(){var s=J.ag.prototype
s.bh=s.i})();(function installTearOffs(){var s=hunkHelpers._static_1,r=hunkHelpers._static_0,q=hunkHelpers._static_2,p=hunkHelpers._instance_2u,o=hunkHelpers._instance_1u,n=hunkHelpers._instance_0u
s(A,"iZ","hS",6)
s(A,"j_","hT",6)
s(A,"j0","hU",6)
r(A,"h2","iT",0)
q(A,"j1","iM",9)
p(A.e.prototype,"gbk","bl",9)
s(A,"j6","ip",7)
s(A,"j4","c1",22)
var m
o(m=A.bY.prototype,"gbv","bw",20)
n(m,"gbx","by",0)})();(function inheritance(){var s=hunkHelpers.mixin,r=hunkHelpers.inherit,q=hunkHelpers.inheritMany
r(A.c,null)
q(A.c,[A.eD,J.ci,A.bx,J.b7,A.n,A.af,A.de,A.d,A.bn,A.bp,A.E,A.az,A.b9,A.bI,A.dj,A.dd,A.be,A.bO,A.bo,A.d6,A.aq,A.bl,A.dF,A.cM,A.Z,A.cJ,A.e5,A.e3,A.bE,A.bS,A.x,A.bG,A.ab,A.e,A.cE,A.bz,A.bP,A.cF,A.bF,A.aj,A.cG,A.a0,A.cK,A.dx,A.r,A.c9,A.cd,A.dY,A.e7,A.bb,A.cH,A.cp,A.by,A.dG,A.cg,A.F,A.t,A.cL,A.aW,A.dc,A.cA,A.cB,A.cC,A.cY,A.cU,A.db,A.cZ,A.aG,A.cN,A.df,A.bY,A.J,A.aV,A.cD,A.dw])
q(J.ci,[J.ck,J.bg,J.bi,J.aI,J.aJ,J.bh,J.aH])
q(J.bi,[J.ag,J.p,A.ah,A.bs])
q(J.ag,[J.cq,J.bB,J.a7])
r(J.cj,A.bx)
r(J.d4,J.p)
q(J.bh,[J.bf,J.cl])
q(A.n,[A.aK,A.a9,A.cm,A.cz,A.cs,A.cI,A.bj,A.c4,A.a3,A.bC,A.cy,A.au,A.cb])
q(A.af,[A.c7,A.c8,A.cx,A.ep,A.er,A.dB,A.dA,A.ee,A.dR,A.dU,A.dg,A.d9,A.ev,A.ew,A.dr,A.ds,A.du,A.dv,A.el,A.ey,A.ex,A.ej,A.ea])
q(A.c7,[A.eu,A.dC,A.dD,A.e4,A.dI,A.dN,A.dM,A.dK,A.dJ,A.dQ,A.dP,A.dO,A.dT,A.dh,A.e2,A.e1,A.dE,A.e_,A.dz,A.dy,A.eh,A.dq,A.dt,A.e9])
q(A.d,[A.i,A.as,A.bH,A.b0])
r(A.bc,A.as)
r(A.b_,A.az)
r(A.bN,A.b_)
r(A.ba,A.b9)
r(A.bt,A.a9)
q(A.cx,[A.cv,A.aF])
r(A.ap,A.bo)
q(A.i,[A.bm,A.bk])
q(A.c8,[A.eq,A.ef,A.ek,A.dS,A.dV,A.da,A.dZ,A.ei,A.eb,A.eg])
r(A.aL,A.ah)
q(A.bs,[A.aM,A.aS])
q(A.aS,[A.bJ,A.bL])
r(A.bK,A.bJ)
r(A.bq,A.bK)
r(A.bM,A.bL)
r(A.br,A.bM)
q(A.bq,[A.aN,A.aO])
q(A.br,[A.aP,A.aQ,A.aR,A.aT,A.aU,A.at,A.ai])
r(A.bT,A.cI)
r(A.a5,A.bG)
r(A.aX,A.bP)
r(A.bR,A.bz)
r(A.aY,A.bR)
r(A.aZ,A.bF)
r(A.av,A.aj)
r(A.co,A.bj)
r(A.cn,A.c9)
q(A.cd,[A.d5,A.dp])
r(A.dX,A.dY)
q(A.a3,[A.bv,A.ch])
q(A.cH,[A.N,A.Q,A.ct,A.cu,A.a4])
q(A.db,[A.cW,A.ca])
s(A.bJ,A.r)
s(A.bK,A.E)
s(A.bL,A.r)
s(A.bM,A.E)
s(A.aX,A.cF)})()
var v={G:typeof self!="undefined"?self:globalThis,typeUniverse:{eC:new Map(),tR:{},eT:{},tPV:{},sEA:[]},mangledGlobalNames:{a:"int",l:"double",aC:"num",L:"String",cR:"bool",t:"Null",m:"List",c:"Object",ar:"Map",q:"JSObject"},mangledNames:{},types:["~()","t(c?)","t()","~(c?,c?)","~(@)","t(c,a_)","~(~())","@(@)","t(@)","~(c,a_)","A<~>()","@(@,L)","@(L)","t(~())","t(@,a_)","~(a,@)","A<c?>(c?)","t(q)","t(~)","~(c)","~(J)","c?()","A<~>(eL)"],interceptorsByTag:null,leafTags:null,arrayRti:Symbol("$ti"),rttc:{"2;":(a,b)=>c=>c instanceof A.bN&&a.b(c.a)&&b.b(c.b)}}
A.id(v.typeUniverse,JSON.parse('{"a7":"ag","cq":"ag","bB":"ag","jx":"ah","p":{"m":["1"],"i":["1"],"q":[],"d":["1"]},"ck":{"cR":[],"k":[]},"bg":{"t":[],"k":[]},"bi":{"q":[]},"ag":{"q":[]},"cj":{"bx":[]},"d4":{"p":["1"],"m":["1"],"i":["1"],"q":[],"d":["1"]},"b7":{"R":["1"]},"bh":{"l":[],"aC":[]},"bf":{"l":[],"a":[],"aC":[],"k":[]},"cl":{"l":[],"aC":[],"k":[]},"aH":{"L":[],"fn":[],"k":[]},"aK":{"n":[]},"i":{"d":["1"]},"bn":{"R":["1"]},"as":{"d":["2"],"d.E":"2"},"bc":{"as":["1","2"],"i":["2"],"d":["2"],"d.E":"2"},"bp":{"R":["2"]},"bN":{"b_":[],"az":[]},"b9":{"ar":["1","2"]},"ba":{"b9":["1","2"],"ar":["1","2"]},"bH":{"d":["1"],"d.E":"1"},"bI":{"R":["1"]},"bt":{"a9":[],"n":[]},"cm":{"n":[]},"cz":{"n":[]},"bO":{"a_":[]},"af":{"ao":[]},"c7":{"ao":[]},"c8":{"ao":[]},"cx":{"ao":[]},"cv":{"ao":[]},"aF":{"ao":[]},"cs":{"n":[]},"ap":{"bo":["1","2"],"fk":["1","2"],"ar":["1","2"]},"bm":{"i":["1"],"d":["1"],"d.E":"1"},"aq":{"R":["1"]},"bk":{"i":["F<1,2>"],"d":["F<1,2>"],"d.E":"F<1,2>"},"bl":{"R":["F<1,2>"]},"b_":{"az":[]},"ai":{"bA":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"E":["a"],"k":[],"r.E":"a"},"ah":{"q":[],"b8":[],"k":[]},"aL":{"ah":[],"q":[],"b8":[],"k":[]},"bs":{"q":[],"u":[]},"cM":{"b8":[]},"aM":{"cV":[],"q":[],"u":[],"k":[]},"aS":{"K":["1"],"q":[],"u":[]},"bq":{"r":["l"],"m":["l"],"K":["l"],"i":["l"],"q":[],"u":[],"d":["l"],"E":["l"]},"br":{"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"E":["a"]},"aN":{"d_":[],"r":["l"],"m":["l"],"K":["l"],"i":["l"],"q":[],"u":[],"d":["l"],"E":["l"],"k":[],"r.E":"l"},"aO":{"d0":[],"r":["l"],"m":["l"],"K":["l"],"i":["l"],"q":[],"u":[],"d":["l"],"E":["l"],"k":[],"r.E":"l"},"aP":{"d1":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"E":["a"],"k":[],"r.E":"a"},"aQ":{"d2":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"E":["a"],"k":[],"r.E":"a"},"aR":{"d3":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"E":["a"],"k":[],"r.E":"a"},"aT":{"dl":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"E":["a"],"k":[],"r.E":"a"},"aU":{"dm":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"E":["a"],"k":[],"r.E":"a"},"at":{"dn":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"E":["a"],"k":[],"r.E":"a"},"cI":{"n":[]},"bT":{"a9":[],"n":[]},"bE":{"cX":["1"]},"bS":{"R":["1"]},"b0":{"d":["1"],"d.E":"1"},"x":{"n":[]},"bG":{"cX":["1"]},"a5":{"bG":["1"],"cX":["1"]},"e":{"A":["1"]},"bP":{"ft":["1"],"fD":["1"],"aw":["1"]},"aX":{"cF":["1"],"bP":["1"],"ft":["1"],"fD":["1"],"aw":["1"]},"aY":{"bR":["1"],"bz":["1"]},"aZ":{"bF":["1"],"cw":["1"],"aw":["1"]},"bF":{"cw":["1"],"aw":["1"]},"bR":{"bz":["1"]},"av":{"aj":["1"]},"cG":{"aj":["@"]},"bo":{"ar":["1","2"]},"bj":{"n":[]},"co":{"n":[]},"cn":{"c9":["c?","L"]},"l":{"aC":[]},"a":{"aC":[]},"m":{"i":["1"],"d":["1"]},"L":{"fn":[]},"cH":{"bd":[]},"c4":{"n":[]},"a9":{"n":[]},"a3":{"n":[]},"bv":{"n":[]},"ch":{"n":[]},"bC":{"n":[]},"cy":{"n":[]},"au":{"n":[]},"cb":{"n":[]},"cp":{"n":[]},"by":{"n":[]},"cL":{"a_":[]},"aW":{"hN":[]},"cC":{"ce":[]},"N":{"bd":[]},"Q":{"bd":[]},"cN":{"hQ":[]},"ct":{"bd":[]},"cu":{"bd":[]},"bY":{"eL":[]},"a4":{"bd":[]},"cV":{"u":[]},"d3":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"bA":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"dn":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"d1":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"dl":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"d2":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"dm":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"d_":{"m":["l"],"i":["l"],"u":[],"d":["l"]},"d0":{"m":["l"],"i":["l"],"u":[],"d":["l"]}}'))
A.ic(v.typeUniverse,JSON.parse('{"i":1,"aS":1,"aj":1,"cd":2}'))
var u={c:"Error handler must accept one Object or one Object and a StackTrace as arguments, and return a value of the returned future's type"}
var t=(function rtii(){var s=A.al
return{r:s("@<~>"),n:s("x"),w:s("Q"),J:s("b8"),V:s("cV"),R:s("aG"),e:s("ce"),x:s("i<@>"),C:s("n"),h4:s("d_"),q:s("d0"),B:s("J"),Z:s("ao"),dQ:s("d1"),an:s("d2"),U:s("d3"),hf:s("d<@>"),A:s("p<aG>"),t:s("p<ce>"),b4:s("p<J>"),f:s("p<c>"),s:s("p<L>"),gn:s("p<@>"),c:s("p<c?>"),T:s("bg"),m:s("q"),g:s("a7"),aU:s("K<@>"),W:s("m<aG>"),cW:s("m<ce>"),j:s("m<@>"),G:s("ar<@,@>"),I:s("ar<L,c?>"),a:s("aL"),gT:s("aM"),al:s("aN"),c2:s("aO"),at:s("aP"),ha:s("aQ"),cv:s("aR"),d:s("aT"),dk:s("aU"),gi:s("at"),Y:s("ai"),P:s("t"),K:s("c"),L:s("jy"),bQ:s("+()"),l:s("a_"),N:s("L"),dm:s("k"),eK:s("a9"),ak:s("u"),h7:s("dl"),bv:s("dm"),go:s("dn"),p:s("bA"),bI:s("bB"),cq:s("N"),g0:s("cA"),dD:s("cB"),h:s("a5<~>"),_:s("e<@>"),fJ:s("e<a>"),D:s("e<~>"),fv:s("bQ<c?>"),y:s("cR"),bN:s("cR(c)"),i:s("l"),z:s("@"),O:s("@()"),v:s("@(c)"),Q:s("@(c,a_)"),S:s("a"),ca:s("ce?"),eH:s("A<t>?"),bX:s("q?"),dE:s("ai?"),X:s("c?"),k:s("c?(c?)"),c8:s("L?"),E:s("bA?"),ev:s("aj<@>?"),F:s("ab<@,@>?"),u:s("cR?"),cD:s("l?"),h6:s("a?"),cg:s("aC?"),b:s("~()?"),o:s("aC"),H:s("~"),M:s("~()"),d5:s("~(c)"),da:s("~(c,a_)"),as:s("~(a,@)")}})();(function constants(){var s=hunkHelpers.makeConstList
B.S=J.ci.prototype
B.a=J.p.prototype
B.c=J.bf.prototype
B.j=J.bh.prototype
B.f=J.aH.prototype
B.T=J.a7.prototype
B.U=J.bi.prototype
B.a1=A.ai.prototype
B.x=J.cq.prototype
B.k=J.bB.prototype
B.n=new A.Q(0,"aac")
B.o=new A.Q(1,"opus")
B.p=new A.Q(2,"vorbis")
B.q=new A.Q(3,"mp3")
B.r=new A.Q(4,"flac")
B.t=function getTagFallback(o) {
  var s = Object.prototype.toString.call(o);
  return s.substring(8, s.length - 1);
}
B.G=function() {
  var toStringFunction = Object.prototype.toString;
  function getTag(o) {
    var s = toStringFunction.call(o);
    return s.substring(8, s.length - 1);
  }
  function getUnknownTag(object, tag) {
    if (/^HTML[A-Z].*Element$/.test(tag)) {
      var name = toStringFunction.call(object);
      if (name == "[object Object]") return null;
      return "HTMLElement";
    }
  }
  function getUnknownTagGenericBrowser(object, tag) {
    if (object instanceof HTMLElement) return "HTMLElement";
    return getUnknownTag(object, tag);
  }
  function prototypeForTag(tag) {
    if (typeof window == "undefined") return null;
    if (typeof window[tag] == "undefined") return null;
    var constructor = window[tag];
    if (typeof constructor != "function") return null;
    return constructor.prototype;
  }
  function discriminator(tag) { return null; }
  var isBrowser = typeof HTMLElement == "function";
  return {
    getTag: getTag,
    getUnknownTag: isBrowser ? getUnknownTagGenericBrowser : getUnknownTag,
    prototypeForTag: prototypeForTag,
    discriminator: discriminator };
}
B.L=function(getTagFallback) {
  return function(hooks) {
    if (typeof navigator != "object") return hooks;
    var userAgent = navigator.userAgent;
    if (typeof userAgent != "string") return hooks;
    if (userAgent.indexOf("DumpRenderTree") >= 0) return hooks;
    if (userAgent.indexOf("Chrome") >= 0) {
      function confirm(p) {
        return typeof window == "object" && window[p] && window[p].name == p;
      }
      if (confirm("Window") && confirm("HTMLElement")) return hooks;
    }
    hooks.getTag = getTagFallback;
  };
}
B.H=function(hooks) {
  if (typeof dartExperimentalFixupGetTag != "function") return hooks;
  hooks.getTag = dartExperimentalFixupGetTag(hooks.getTag);
}
B.K=function(hooks) {
  if (typeof navigator != "object") return hooks;
  var userAgent = navigator.userAgent;
  if (typeof userAgent != "string") return hooks;
  if (userAgent.indexOf("Firefox") == -1) return hooks;
  var getTag = hooks.getTag;
  var quickMap = {
    "BeforeUnloadEvent": "Event",
    "DataTransfer": "Clipboard",
    "GeoGeolocation": "Geolocation",
    "Location": "!Location",
    "WorkerMessageEvent": "MessageEvent",
    "XMLDocument": "!Document"};
  function getTagFirefox(o) {
    var tag = getTag(o);
    return quickMap[tag] || tag;
  }
  hooks.getTag = getTagFirefox;
}
B.J=function(hooks) {
  if (typeof navigator != "object") return hooks;
  var userAgent = navigator.userAgent;
  if (typeof userAgent != "string") return hooks;
  if (userAgent.indexOf("Trident/") == -1) return hooks;
  var getTag = hooks.getTag;
  var quickMap = {
    "BeforeUnloadEvent": "Event",
    "DataTransfer": "Clipboard",
    "HTMLDDElement": "HTMLElement",
    "HTMLDTElement": "HTMLElement",
    "HTMLPhraseElement": "HTMLElement",
    "Position": "Geoposition"
  };
  function getTagIE(o) {
    var tag = getTag(o);
    var newTag = quickMap[tag];
    if (newTag) return newTag;
    if (tag == "Object") {
      if (window.DataView && (o instanceof window.DataView)) return "DataView";
    }
    return tag;
  }
  function prototypeForTagIE(tag) {
    var constructor = window[tag];
    if (constructor == null) return null;
    return constructor.prototype;
  }
  hooks.getTag = getTagIE;
  hooks.prototypeForTag = prototypeForTagIE;
}
B.I=function(hooks) {
  var getTag = hooks.getTag;
  var prototypeForTag = hooks.prototypeForTag;
  function getTagFixed(o) {
    var tag = getTag(o);
    if (tag == "Document") {
      if (!!o.xmlVersion) return "!Document";
      return "!HTMLDocument";
    }
    return tag;
  }
  function prototypeForTagFixed(tag) {
    if (tag == "Document") return null;
    return prototypeForTag(tag);
  }
  hooks.getTag = getTagFixed;
  hooks.prototypeForTag = prototypeForTagFixed;
}
B.u=function(hooks) { return hooks; }

B.M=new A.cn()
B.N=new A.cp()
B.d=new A.de()
B.al=new A.ct(0,"dart")
B.am=new A.cu(1,"js")
B.O=new A.df()
B.i=new A.dp()
B.b=new A.dx()
B.v=new A.cG()
B.e=new A.cL()
B.P=new A.ca("webcodecs-worker","decoder produced a non-browser frame")
B.Q=new A.bb(0)
B.w=new A.bb(2e4)
B.m=new A.a4(1,1,"bye")
B.R=new A.J(B.m,0,0,null,null)
B.V=new A.d5(null)
B.l=new A.a4(0,0,"hello")
B.aj=new A.a4(2,2,"message")
B.ak=new A.a4(3,3,"request")
B.D=new A.a4(4,4,"response")
B.h=new A.a4(5,5,"error")
B.W=s([B.l,B.m,B.aj,B.ak,B.D,B.h],A.al("p<a4>"))
B.X=s([],t.A)
B.Y=s([],t.t)
B.y=new A.N(0,"h264")
B.z=new A.N(1,"hevc")
B.A=new A.N(2,"av1")
B.B=new A.N(3,"vp9")
B.C=new A.N(4,"vp8")
B.ag=new A.N(5,"mjpeg")
B.ah=new A.N(6,"prores")
B.ai=new A.N(7,"custom")
B.Z=s([B.y,B.z,B.A,B.B,B.C,B.ag,B.ah,B.ai],A.al("p<N>"))
B.E=new A.Q(5,"pcmS16le")
B.F=new A.Q(6,"pcmF32le")
B.a_=s([B.n,B.o,B.p,B.q,B.r,B.E,B.F],A.al("p<Q>"))
B.a2={}
B.a0=new A.ba(B.a2,[],A.al("ba<L,L>"))
B.a3=A.Y("b8")
B.a4=A.Y("cV")
B.a5=A.Y("d_")
B.a6=A.Y("d0")
B.a7=A.Y("d1")
B.a8=A.Y("d2")
B.a9=A.Y("d3")
B.aa=A.Y("q")
B.ab=A.Y("c")
B.ac=A.Y("dl")
B.ad=A.Y("dm")
B.ae=A.Y("dn")
B.af=A.Y("bA")})();(function staticFields(){$.dW=null
$.O=A.z([],t.f)
$.fo=null
$.fa=null
$.f9=null
$.h7=null
$.h1=null
$.hb=null
$.em=null
$.es=null
$.f1=null
$.e0=A.z([],A.al("p<m<c>?>"))
$.b1=null
$.c_=null
$.c0=null
$.eS=!1
$.f=B.b})();(function lazyInitializers(){var s=hunkHelpers.lazyFinal
s($,"jv","hf",()=>A.en("_$dart_dartClosure"))
s($,"ju","f5",()=>A.en("_$dart_dartClosure_dartJSInterop"))
s($,"jR","hs",()=>B.b.bY(new A.eu(),A.al("A<~>")))
s($,"jO","hr",()=>A.z([new J.cj()],A.al("p<bx>")))
s($,"jA","hg",()=>A.aa(A.dk({
toString:function(){return"$receiver$"}})))
s($,"jB","hh",()=>A.aa(A.dk({$method$:null,
toString:function(){return"$receiver$"}})))
s($,"jC","hi",()=>A.aa(A.dk(null)))
s($,"jD","hj",()=>A.aa(function(){var $argumentsExpr$="$arguments$"
try{null.$method$($argumentsExpr$)}catch(r){return r.message}}()))
s($,"jG","hm",()=>A.aa(A.dk(void 0)))
s($,"jH","hn",()=>A.aa(function(){var $argumentsExpr$="$arguments$"
try{(void 0).$method$($argumentsExpr$)}catch(r){return r.message}}()))
s($,"jF","hl",()=>A.aa(A.fx(null)))
s($,"jE","hk",()=>A.aa(function(){try{null.$method$}catch(r){return r.message}}()))
s($,"jJ","hp",()=>A.aa(A.fx(void 0)))
s($,"jI","ho",()=>A.aa(function(){try{(void 0).$method$}catch(r){return r.message}}()))
s($,"jM","f6",()=>A.hR())
s($,"jw","ez",()=>$.hs())
s($,"jN","cT",()=>A.h8(B.ab))
s($,"jL","hq",()=>new A.dw(A.eF(t.S,A.al("jK(bA)"))))})();(function nativeSupport(){!function(){var s=function(a){var m={}
m[a]=1
return Object.keys(hunkHelpers.convertToFastObject(m))[0]}
v.getIsolateTag=function(a){return s("___dart_"+a+v.isolateTag)}
var r="___dart_isolate_tags_"
var q=Object[r]||(Object[r]=Object.create(null))
var p="_ZxYxX"
for(var o=0;;o++){var n=s(p+"_"+o+"_")
if(!(n in q)){q[n]=1
v.isolateTag=n
break}}v.dispatchPropertyName=v.getIsolateTag("dispatch_record")}()
hunkHelpers.setOrUpdateInterceptorsByTag({SharedArrayBuffer:A.ah,ArrayBuffer:A.aL,ArrayBufferView:A.bs,DataView:A.aM,Float32Array:A.aN,Float64Array:A.aO,Int16Array:A.aP,Int32Array:A.aQ,Int8Array:A.aR,Uint16Array:A.aT,Uint32Array:A.aU,Uint8ClampedArray:A.at,CanvasPixelArray:A.at,Uint8Array:A.ai})
hunkHelpers.setOrUpdateLeafTags({SharedArrayBuffer:true,ArrayBuffer:true,ArrayBufferView:false,DataView:true,Float32Array:true,Float64Array:true,Int16Array:true,Int32Array:true,Int8Array:true,Uint16Array:true,Uint32Array:true,Uint8ClampedArray:true,CanvasPixelArray:true,Uint8Array:false})
A.aS.$nativeSuperclassTag="ArrayBufferView"
A.bJ.$nativeSuperclassTag="ArrayBufferView"
A.bK.$nativeSuperclassTag="ArrayBufferView"
A.bq.$nativeSuperclassTag="ArrayBufferView"
A.bL.$nativeSuperclassTag="ArrayBufferView"
A.bM.$nativeSuperclassTag="ArrayBufferView"
A.br.$nativeSuperclassTag="ArrayBufferView"})()
Function.prototype.$1=function(a){return this(a)}
Function.prototype.$2=function(a,b){return this(a,b)}
Function.prototype.$0=function(){return this()}
Function.prototype.$3=function(a,b,c){return this(a,b,c)}
Function.prototype.$4=function(a,b,c,d){return this(a,b,c,d)}
Function.prototype.$5=function(a,b,c,d,e){return this(a,b,c,d,e)}
Function.prototype.$6=function(a,b,c,d,e,f){return this(a,b,c,d,e,f)}
Function.prototype.$1$1=function(a){return this(a)}
convertAllToFastObject(w)
convertToFastObject($);(function(a){if(typeof document==="undefined"){a(null)
return}if(typeof document.currentScript!="undefined"){a(document.currentScript)
return}var s=document.scripts
function onLoad(b){for(var q=0;q<s.length;++q){s[q].removeEventListener("load",onLoad,false)}a(b.target)}for(var r=0;r<s.length;++r){s[r].addEventListener("load",onLoad,false)}})(function(a){v.currentScript=a
var s=A.jl
if(typeof dartMainRunner==="function"){dartMainRunner(s,[])}else{s([])}})})()
//# sourceMappingURL=codec_worker.dart.js.map
