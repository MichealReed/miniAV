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
if(a[b]!==s){A.kP(b)}a[b]=r}var q=a[b]
a[c]=function(){return q}
return q}}function makeConstList(a,b){if(b!=null)A.i(a,b)
a.$flags=7
return a}function convertToFastObject(a){function t(){}t.prototype=a
new t()
return a}function convertAllToFastObject(a){for(var s=0;s<a.length;++s){convertToFastObject(a[s])}}var y=0
function instanceTearOffGetter(a,b){var s=null
return a?function(c){if(s===null)s=A.fG(b)
return new s(c,this)}:function(){if(s===null)s=A.fG(b)
return new s(this,null)}}function staticTearOffGetter(a){var s=null
return function(){if(s===null)s=A.fG(a).prototype
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
fM(a,b,c,d){return{i:a,p:b,e:c,x:d}},
f_(a){var s,r,q,p,o,n=a[v.dispatchPropertyName]
if(n==null)if($.fJ==null){A.kA()
n=a[v.dispatchPropertyName]}if(n!=null){s=n.p
if(!1===s)return n.i
if(!0===s)return a
r=Object.getPrototypeOf(a)
if(s===r)return n.i
if(n.e===r)throw A.a(A.hh("Return interceptor for "+A.o(s(a,n))))}q=a.constructor
if(q==null)p=null
else{o=$.es
if(o==null)o=$.es=v.getIsolateTag("_$dart_js")
p=q[o]}if(p!=null)return p
p=A.kF(a)
if(p!=null)return p
if(typeof a=="function")return B.aw
s=Object.getPrototypeOf(a)
if(s==null)return B.O
if(s===Object.prototype)return B.O
if(typeof q=="function"){o=$.es
if(o==null)o=$.es=v.getIsolateTag("_$dart_js")
Object.defineProperty(q,o,{value:B.p,enumerable:false,writable:true,configurable:true})
return B.p}return B.p},
iw(a,b){if(a<0||a>4294967295)throw A.a(A.ad(a,0,4294967295,"length",null))
return J.ix(new Array(a),b)},
ix(a,b){var s=A.i(a,b.h("p<0>"))
s.$flags=1
return s},
ao(a){if(typeof a=="number"){if(Math.floor(a)==a)return J.bF.prototype
return J.cH.prototype}if(typeof a=="string")return J.b2.prototype
if(a==null)return J.bG.prototype
if(typeof a=="boolean")return J.cG.prototype
if(Array.isArray(a))return J.p.prototype
if(typeof a!="object"){if(typeof a=="function")return J.ac.prototype
if(typeof a=="symbol")return J.b4.prototype
if(typeof a=="bigint")return J.b3.prototype
return a}if(a instanceof A.d)return a
return J.f_(a)},
bv(a){if(typeof a=="string")return J.b2.prototype
if(a==null)return a
if(Array.isArray(a))return J.p.prototype
if(typeof a!="object"){if(typeof a=="function")return J.ac.prototype
if(typeof a=="symbol")return J.b4.prototype
if(typeof a=="bigint")return J.b3.prototype
return a}if(a instanceof A.d)return a
return J.f_(a)},
hT(a){if(a==null)return a
if(Array.isArray(a))return J.p.prototype
if(typeof a!="object"){if(typeof a=="function")return J.ac.prototype
if(typeof a=="symbol")return J.b4.prototype
if(typeof a=="bigint")return J.b3.prototype
return a}if(a instanceof A.d)return a
return J.f_(a)},
eZ(a){if(a==null)return a
if(typeof a!="object"){if(typeof a=="function")return J.ac.prototype
if(typeof a=="symbol")return J.b4.prototype
if(typeof a=="bigint")return J.b3.prototype
return a}if(a instanceof A.d)return a
return J.f_(a)},
di(a,b){if(a==null)return b==null
if(typeof a!="object")return b!=null&&a===b
return J.ao(a).H(a,b)},
fQ(a,b){if(typeof b==="number")if(Array.isArray(a)||typeof a=="string"||A.kD(a,a[v.dispatchPropertyName]))if(b>>>0===b&&b<a.length)return a[b]
return J.bv(a).m(a,b)},
id(a,b,c){return J.eZ(a).b8(a,b,c)},
fd(a,b){return J.eZ(a).bb(a,b)},
dj(a,b,c){return J.eZ(a).a6(a,b,c)},
T(a){return J.ao(a).gp(a)},
cr(a){return J.hT(a).gK(a)},
fR(a){return J.bv(a).gk(a)},
bx(a){return J.ao(a).gl(a)},
aY(a){return J.ao(a).i(a)},
cE:function cE(){},
cG:function cG(){},
bG:function bG(){},
bI:function bI(){},
av:function av(){},
cM:function cM(){},
bW:function bW(){},
ac:function ac(){},
b3:function b3(){},
b4:function b4(){},
p:function p(a){this.$ti=a},
cF:function cF(){},
dw:function dw(a){this.$ti=a},
bz:function bz(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
bH:function bH(){},
bF:function bF(){},
cH:function cH(){},
b2:function b2(){}},A={fg:function fg(){},
X(a,b){a=a+b&536870911
a=a+((a&524287)<<10)&536870911
return a^a>>>6},
dR(a){a=a+((a&67108863)<<3)&536870911
a^=a>>>11
return a+((a&16383)<<15)&536870911},
fF(a,b,c){return a},
fL(a){var s,r
for(s=$.Y.length,r=0;r<s;++r)if(a===$.Y[r])return!0
return!1},
it(){return new A.ay("No element")},
e9:function e9(a){this.a=0
this.b=a},
b5:function b5(a){this.a=a},
cx:function cx(a){this.a=a},
f6:function f6(){},
dK:function dK(){},
bD:function bD(){},
bK:function bK(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
Q:function Q(){},
aL:function aL(){},
bg:function bg(){},
i_(a){var s=v.mangledGlobalNames[a]
if(s!=null)return s
return"minified:"+a},
kD(a,b){var s
if(b!=null){s=b.x
if(s!=null)return s}return t.aU.b(a)},
o(a){var s
if(typeof a=="string")return a
if(typeof a=="number"){if(a!==0)return""+a}else if(!0===a)return"true"
else if(!1===a)return"false"
else if(a==null)return"null"
s=J.aY(a)
return s},
bQ(a){var s,r=$.h6
if(r==null)r=$.h6=Symbol("identityHashCode")
s=a[r]
if(s==null){s=Math.random()*0x3fffffff|0
a[r]=s}return s},
cN(a){var s,r,q,p
if(a instanceof A.d)return A.O(A.aV(a),null)
s=J.ao(a)
if(s===B.av||s===B.ax||t.bI.b(a)){r=B.u(a)
if(r!=="Object"&&r!=="")return r
q=a.constructor
if(typeof q=="function"){p=q.name
if(typeof p=="string"&&p!=="Object"&&p!=="")return p}}return A.O(A.aV(a),null)},
h7(a){var s,r,q
if(a==null||typeof a=="number"||A.dc(a))return J.aY(a)
if(typeof a=="string")return JSON.stringify(a)
if(a instanceof A.aq)return a.i(0)
if(a instanceof A.aQ)return a.b7(!0)
s=$.ib()
for(r=0;r<1;++r){q=s[r].cl(a)
if(q!=null)return q}return"Instance of '"+A.cN(a)+"'"},
h5(a){var s,r,q,p,o=a.length
if(o<=500)return String.fromCharCode.apply(null,a)
for(s="",r=0;r<o;r=q){q=r+500
p=q<o?q:o
s+=String.fromCharCode.apply(null,a.slice(r,p))}return s},
iN(a){var s,r,q,p=A.i([],t.t)
for(s=a.length,r=0;r<a.length;a.length===s||(0,A.cq)(a),++r){q=a[r]
if(!A.cl(q))throw A.a(A.aU(q))
if(q<=65535)B.b.j(p,q)
else if(q<=1114111){B.b.j(p,55296+(B.a.F(q-65536,10)&1023))
B.b.j(p,56320+(q&1023))}else throw A.a(A.aU(q))}return A.h5(p)},
iM(a){var s,r,q
for(s=a.length,r=0;r<s;++r){q=a[r]
if(!A.cl(q))throw A.a(A.aU(q))
if(q<0)throw A.a(A.aU(q))
if(q>65535)return A.iN(a)}return A.h5(a)},
I(a){var s
if(a<=65535)return String.fromCharCode(a)
if(a<=1114111){s=a-65536
return String.fromCharCode((B.a.F(s,10)|55296)>>>0,s&1023|56320)}throw A.a(A.ad(a,0,1114111,null,null))},
iL(a){var s=a.$thrownJsError
if(s==null)return null
return A.S(s)},
h8(a,b){var s
if(a.$thrownJsError==null){s=new Error()
A.F(a,s)
a.$thrownJsError=s
s.stack=b.i(0)}},
f0(a){throw A.a(A.aU(a))},
b(a,b){if(a==null)J.fR(a)
throw A.a(A.eX(a,b))},
eX(a,b){var s,r="index"
if(!A.cl(b))return new A.a2(!0,b,r,null)
s=A.u(J.fR(a))
if(b<0||b>=s)return A.is(b,s,a,r)
return new A.bR(null,null,!0,b,r,"Value not in range")},
ks(a,b,c){if(a>c)return A.ad(a,0,c,"start",null)
if(b!=null)if(b<a||b>c)return A.ad(b,a,c,"end",null)
return new A.a2(!0,b,"end",null)},
aU(a){return new A.a2(!0,a,null,null)},
a(a){return A.F(a,new Error())},
F(a,b){var s
if(a==null)a=new A.af()
b.dartException=a
s=A.kQ
if("defineProperty" in Object){Object.defineProperty(b,"message",{get:s})
b.name=""}else b.toString=s
return b},
kQ(){return J.aY(this.dartException)},
D(a,b){throw A.F(a,b==null?new Error():b)},
K(a,b,c){var s
if(b==null)b=0
if(c==null)c=0
s=Error()
A.D(A.ju(a,b,c),s)},
ju(a,b,c){var s,r,q,p,o,n,m,l,k
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
return new A.bX("'"+s+"': Cannot "+o+" "+l+k+n)},
cq(a){throw A.a(A.b_(a))},
ag(a){var s,r,q,p,o,n
a=A.hZ(a.replace(String({}),"$receiver$"))
s=a.match(/\\\$[a-zA-Z]+\\\$/g)
if(s==null)s=A.i([],t.s)
r=s.indexOf("\\$arguments\\$")
q=s.indexOf("\\$argumentsExpr\\$")
p=s.indexOf("\\$expr\\$")
o=s.indexOf("\\$method\\$")
n=s.indexOf("\\$receiver\\$")
return new A.dS(a.replace(new RegExp("\\\\\\$arguments\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$argumentsExpr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$expr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$method\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$receiver\\\\\\$","g"),"((?:x|[^x])*)"),r,q,p,o,n)},
dT(a){return function($expr$){var $argumentsExpr$="$arguments$"
try{$expr$.$method$($argumentsExpr$)}catch(s){return s.message}}(a)},
hg(a){return function($expr$){try{$expr$.$method$}catch(s){return s.message}}(a)},
fh(a,b){var s=b==null,r=s?null:b.method
return new A.cI(a,r,s?null:b.receiver)},
P(a){var s
if(a==null)return new A.dI(a)
if(a instanceof A.bE){s=a.a
return A.aB(a,s==null?A.a0(s):s)}if(typeof a!=="object")return a
if("dartException" in a)return A.aB(a,a.dartException)
return A.ke(a)},
aB(a,b){if(t.C.b(b))if(b.$thrownJsError==null)b.$thrownJsError=a
return b},
ke(a){var s,r,q,p,o,n,m,l,k,j,i,h,g
if(!("message" in a))return a
s=a.message
if("number" in a&&typeof a.number=="number"){r=a.number
q=r&65535
if((B.a.F(r,16)&8191)===10)switch(q){case 438:return A.aB(a,A.fh(A.o(s)+" (Error "+q+")",null))
case 445:case 5007:A.o(s)
return A.aB(a,new A.bP())}}if(a instanceof TypeError){p=$.i0()
o=$.i1()
n=$.i2()
m=$.i3()
l=$.i6()
k=$.i7()
j=$.i5()
$.i4()
i=$.i9()
h=$.i8()
g=p.E(s)
if(g!=null)return A.aB(a,A.fh(A.al(s),g))
else{g=o.E(s)
if(g!=null){g.method="call"
return A.aB(a,A.fh(A.al(s),g))}else if(n.E(s)!=null||m.E(s)!=null||l.E(s)!=null||k.E(s)!=null||j.E(s)!=null||m.E(s)!=null||i.E(s)!=null||h.E(s)!=null){A.al(s)
return A.aB(a,new A.bP())}}return A.aB(a,new A.cU(typeof s=="string"?s:""))}if(a instanceof RangeError){if(typeof s=="string"&&s.indexOf("call stack")!==-1)return new A.bT()
s=function(b){try{return String(b)}catch(f){}return null}(a)
return A.aB(a,new A.a2(!1,null,null,typeof s=="string"?s.replace(/^RangeError:\s*/,""):s))}if(typeof InternalError=="function"&&a instanceof InternalError)if(typeof s=="string"&&s==="too much recursion")return new A.bT()
return a},
S(a){var s
if(a instanceof A.bE)return a.b
if(a==null)return new A.ca(a)
s=a.$cachedTrace
if(s!=null)return s
s=new A.ca(a)
if(typeof a==="object")a.$cachedTrace=s
return s},
hW(a){if(a==null)return J.T(a)
if(typeof a=="object")return A.bQ(a)
return J.T(a)},
kw(a,b){var s,r,q,p=a.length
for(s=0;s<p;s=q){r=s+1
q=r+1
b.t(0,a[s],a[r])}return b},
jD(a,b,c,d,e,f){t.Z.a(a)
switch(A.u(b)){case 0:return a.$0()
case 1:return a.$1(c)
case 2:return a.$2(c,d)
case 3:return a.$3(c,d,e)
case 4:return a.$4(c,d,e,f)}throw A.a(new A.ec("Unsupported number of arguments for wrapped closure"))},
bt(a,b){var s=a.$identity
if(!!s)return s
s=A.kp(a,b)
a.$identity=s
return s},
kp(a,b){var s
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
return function(c,d,e){return function(f,g,h,i){return e(c,d,f,g,h,i)}}(a,b,A.jD)},
il(a2){var s,r,q,p,o,n,m,l,k,j,i=a2.co,h=a2.iS,g=a2.iI,f=a2.nDA,e=a2.aI,d=a2.fs,c=a2.cs,b=d[0],a=c[0],a0=i[b],a1=a2.fT
a1.toString
s=h?Object.create(new A.cQ().constructor.prototype):Object.create(new A.aZ(null,null).constructor.prototype)
s.$initialize=s.constructor
r=h?function static_tear_off(){this.$initialize()}:function tear_off(a3,a4){this.$initialize(a3,a4)}
s.constructor=r
r.prototype=s
s.$_name=b
s.$_target=a0
q=!h
if(q)p=A.fX(b,a0,g,f)
else{s.$static_name=b
p=a0}s.$S=A.ih(a1,h,g)
s[a]=p
for(o=p,n=1;n<d.length;++n){m=d[n]
if(typeof m=="string"){l=i[m]
k=m
m=l}else k=""
j=c[n]
if(j!=null){if(q)m=A.fX(k,m,g,f)
s[j]=m}if(n===e)o=m}s.$C=o
s.$R=a2.rC
s.$D=a2.dV
return r},
ih(a,b,c){if(typeof a=="number")return a
if(typeof a=="string"){if(b)throw A.a("Cannot compute signature for static tearoff.")
return function(d,e){return function(){return e(this,d)}}(a,A.ie)}throw A.a("Error in functionType of tearoff")},
ii(a,b,c,d){var s=A.fW
switch(b?-1:a){case 0:return function(e,f){return function(){return f(this)[e]()}}(c,s)
case 1:return function(e,f){return function(g){return f(this)[e](g)}}(c,s)
case 2:return function(e,f){return function(g,h){return f(this)[e](g,h)}}(c,s)
case 3:return function(e,f){return function(g,h,i){return f(this)[e](g,h,i)}}(c,s)
case 4:return function(e,f){return function(g,h,i,j){return f(this)[e](g,h,i,j)}}(c,s)
case 5:return function(e,f){return function(g,h,i,j,k){return f(this)[e](g,h,i,j,k)}}(c,s)
default:return function(e,f){return function(){return e.apply(f(this),arguments)}}(d,s)}},
fX(a,b,c,d){if(c)return A.ik(a,b,d)
return A.ii(b.length,d,a,b)},
ij(a,b,c,d){var s=A.fW,r=A.ig
switch(b?-1:a){case 0:throw A.a(new A.cP("Intercepted function with no arguments."))
case 1:return function(e,f,g){return function(){return f(this)[e](g(this))}}(c,r,s)
case 2:return function(e,f,g){return function(h){return f(this)[e](g(this),h)}}(c,r,s)
case 3:return function(e,f,g){return function(h,i){return f(this)[e](g(this),h,i)}}(c,r,s)
case 4:return function(e,f,g){return function(h,i,j){return f(this)[e](g(this),h,i,j)}}(c,r,s)
case 5:return function(e,f,g){return function(h,i,j,k){return f(this)[e](g(this),h,i,j,k)}}(c,r,s)
case 6:return function(e,f,g){return function(h,i,j,k,l){return f(this)[e](g(this),h,i,j,k,l)}}(c,r,s)
default:return function(e,f,g){return function(){var q=[g(this)]
Array.prototype.push.apply(q,arguments)
return e.apply(f(this),q)}}(d,r,s)}},
ik(a,b,c){var s,r
if($.fU==null)$.fU=A.fT("interceptor")
if($.fV==null)$.fV=A.fT("receiver")
s=b.length
r=A.ij(s,c,a,b)
return r},
fG(a){return A.il(a)},
ie(a,b){return A.ci(v.typeUniverse,A.aV(a.a),b)},
fW(a){return a.a},
ig(a){return a.b},
fT(a){var s,r,q,p=new A.aZ("receiver","interceptor"),o=Object.getOwnPropertyNames(p)
o.$flags=1
s=o
for(o=s.length,r=0;r<o;++r){q=s[r]
if(p[q]===a)return q}throw A.a(A.by("Field name "+a+" not found.",null))},
kx(a){return v.getIsolateTag(a)},
lb(a,b,c){Object.defineProperty(a,b,{value:c,enumerable:false,writable:true,configurable:true})},
kF(a){var s,r,q,p,o,n=A.al($.hV.$1(a)),m=$.eY[n]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.f4[n]
if(s!=null)return s
r=v.interceptorsByTag[n]
if(r==null){q=A.fv($.hR.$2(a,n))
if(q!=null){m=$.eY[q]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.f4[q]
if(s!=null)return s
r=v.interceptorsByTag[q]
n=q}}if(r==null)return null
s=r.prototype
p=n[0]
if(p==="!"){m=A.f5(s)
$.eY[n]=m
Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}if(p==="~"){$.f4[n]=s
return s}if(p==="-"){o=A.f5(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}if(p==="+")return A.hX(a,s)
if(p==="*")throw A.a(A.hh(n))
if(v.leafTags[n]===true){o=A.f5(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}else return A.hX(a,s)},
hX(a,b){var s=Object.getPrototypeOf(a)
Object.defineProperty(s,v.dispatchPropertyName,{value:J.fM(b,s,null,null),enumerable:false,writable:true,configurable:true})
return b},
f5(a){return J.fM(a,!1,null,!!a.$iV)},
kH(a,b,c){var s=b.prototype
if(v.leafTags[a]===true)return A.f5(s)
else return J.fM(s,c,null,null)},
kA(){if(!0===$.fJ)return
$.fJ=!0
A.kB()},
kB(){var s,r,q,p,o,n,m,l
$.eY=Object.create(null)
$.f4=Object.create(null)
A.kz()
s=v.interceptorsByTag
r=Object.getOwnPropertyNames(s)
if(typeof window!="undefined"){window
q=function(){}
for(p=0;p<r.length;++p){o=r[p]
n=$.hY.$1(o)
if(n!=null){m=A.kH(o,s[o],n)
if(m!=null){Object.defineProperty(n,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
q.prototype=n}}}}for(p=0;p<r.length;++p){o=r[p]
if(/^[A-Za-z_]/.test(o)){l=s[o]
s["!"+o]=l
s["~"+o]=l
s["-"+o]=l
s["+"+o]=l
s["*"+o]=l}}},
kz(){var s,r,q,p,o,n,m=B.Z()
m=A.bs(B.a_,A.bs(B.a0,A.bs(B.v,A.bs(B.v,A.bs(B.a1,A.bs(B.a2,A.bs(B.a3(B.u),m)))))))
if(typeof dartNativeDispatchHooksTransformer!="undefined"){s=dartNativeDispatchHooksTransformer
if(typeof s=="function")s=[s]
if(Array.isArray(s))for(r=0;r<s.length;++r){q=s[r]
if(typeof q=="function")m=q(m)||m}}p=m.getTag
o=m.getUnknownTag
n=m.prototypeForTag
$.hV=new A.f1(p)
$.hR=new A.f2(o)
$.hY=new A.f3(n)},
bs(a,b){return a(b)||b},
kr(a,b){var s=b.length,r=v.rttc[""+s+";"+a]
if(r==null)return null
if(s===0)return r
if(s===r.length)return r.apply(null,b)
return r(b)},
ku(a){if(a.indexOf("$",0)>=0)return a.replace(/\$/g,"$$$$")
return a},
hZ(a){if(/[[\]{}()*+?.\\^$|]/.test(a))return a.replace(/[[\]{}()*+?.\\^$|]/g,"\\$&")
return a},
fN(a,b,c){var s=A.kO(a,b,c)
return s},
kO(a,b,c){var s,r,q
if(b===""){if(a==="")return c
s=a.length
for(r=c,q=0;q<s;++q)r=r+a[q]+c
return r.charCodeAt(0)==0?r:r}if(a.indexOf(b,0)<0)return a
if(a.length<500||c.indexOf("$",0)>=0)return a.split(b).join(c)
return a.replace(new RegExp(A.hZ(b),"g"),A.ku(c))},
c8:function c8(a,b){this.a=a
this.b=b},
bB:function bB(){},
bC:function bC(a,b,c){this.a=a
this.b=b
this.$ti=c},
bS:function bS(){},
dS:function dS(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
bP:function bP(){},
cI:function cI(a,b,c){this.a=a
this.b=b
this.c=c},
cU:function cU(a){this.a=a},
dI:function dI(a){this.a=a},
bE:function bE(a,b){this.a=a
this.b=b},
ca:function ca(a){this.a=a
this.b=null},
aq:function aq(){},
cv:function cv(){},
cw:function cw(){},
cS:function cS(){},
cQ:function cQ(){},
aZ:function aZ(a,b){this.a=a
this.b=b},
cP:function cP(a){this.a=a},
aF:function aF(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
dy:function dy(a,b){this.a=a
this.b=b
this.c=null},
dz:function dz(a,b){this.a=a
this.$ti=b},
aG:function aG(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=null
_.$ti=d},
f1:function f1(a){this.a=a},
f2:function f2(a){this.a=a},
f3:function f3(a){this.a=a},
aQ:function aQ(){},
bl:function bl(){},
kP(a){throw A.F(new A.b5("Field '"+a+"' has been assigned during initialization."),new Error())},
iZ(){var s=new A.e8()
return s.b=s},
e8:function e8(){this.b=null},
aR(a,b,c){},
bo(a){return a},
iF(a,b,c){var s
A.aR(a,b,c)
s=new DataView(a,b,c)
return s},
iG(a,b,c){A.aR(a,b,c)
return new Float32Array(a,b,c)},
iH(a,b,c){A.aR(a,b,c)
return new Int32Array(a,b,c)},
iI(a){return new Uint8Array(a)},
iJ(a,b,c){A.aR(a,b,c)
return c==null?new Uint8Array(a,b):new Uint8Array(a,b,c)},
am(a,b,c){if(a>>>0!==a||a>=c)throw A.a(A.eX(b,a))},
jq(a,b,c){var s
if(!(a>>>0!==a))s=b>>>0!==b||a>b||b>c
else s=!0
if(s)throw A.a(A.ks(a,b,c))
return b},
aw:function aw(){},
b6:function b6(){},
bO:function bO(){},
d8:function d8(a){this.a=a},
aI:function aI(){},
H:function H(){},
bN:function bN(){},
W:function W(){},
aJ:function aJ(){},
b7:function b7(){},
b8:function b8(){},
b9:function b9(){},
ba:function ba(){},
bb:function bb(){},
bc:function bc(){},
aK:function aK(){},
ax:function ax(){},
c4:function c4(){},
c5:function c5(){},
c6:function c6(){},
c7:function c7(){},
fl(a,b){var s=b.c
return s==null?b.c=A.cg(a,"L",[b.x]):s},
ha(a){var s=a.w
if(s===6||s===7)return A.ha(a.x)
return s===11||s===12},
iO(a){return a.as},
bu(a){return A.eF(v.typeUniverse,a,!1)},
aS(a1,a2,a3,a4){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=a2.w
switch(a0){case 5:case 1:case 2:case 3:case 4:return a2
case 6:s=a2.x
r=A.aS(a1,s,a3,a4)
if(r===s)return a2
return A.hu(a1,r,!0)
case 7:s=a2.x
r=A.aS(a1,s,a3,a4)
if(r===s)return a2
return A.ht(a1,r,!0)
case 8:q=a2.y
p=A.br(a1,q,a3,a4)
if(p===q)return a2
return A.cg(a1,a2.x,p)
case 9:o=a2.x
n=A.aS(a1,o,a3,a4)
m=a2.y
l=A.br(a1,m,a3,a4)
if(n===o&&l===m)return a2
return A.fr(a1,n,l)
case 10:k=a2.x
j=a2.y
i=A.br(a1,j,a3,a4)
if(i===j)return a2
return A.hv(a1,k,i)
case 11:h=a2.x
g=A.aS(a1,h,a3,a4)
f=a2.y
e=A.ka(a1,f,a3,a4)
if(g===h&&e===f)return a2
return A.hs(a1,g,e)
case 12:d=a2.y
a4+=d.length
c=A.br(a1,d,a3,a4)
o=a2.x
n=A.aS(a1,o,a3,a4)
if(c===d&&n===o)return a2
return A.fs(a1,n,c,!0)
case 13:b=a2.x
if(b<a4)return a2
a=a3[b-a4]
if(a==null)return a2
return a
default:throw A.a(A.ct("Attempted to substitute unexpected RTI kind "+a0))}},
br(a,b,c,d){var s,r,q,p,o=b.length,n=A.eH(o)
for(s=!1,r=0;r<o;++r){q=b[r]
p=A.aS(a,q,c,d)
if(p!==q)s=!0
n[r]=p}return s?n:b},
kb(a,b,c,d){var s,r,q,p,o,n,m=b.length,l=A.eH(m)
for(s=!1,r=0;r<m;r+=3){q=b[r]
p=b[r+1]
o=b[r+2]
n=A.aS(a,o,c,d)
if(n!==o)s=!0
l.splice(r,3,q,p,n)}return s?l:b},
ka(a,b,c,d){var s,r=b.a,q=A.br(a,r,c,d),p=b.b,o=A.br(a,p,c,d),n=b.c,m=A.kb(a,n,c,d)
if(q===r&&o===p&&m===n)return b
s=new A.d3()
s.a=q
s.b=o
s.c=m
return s},
i(a,b){a[v.arrayRti]=b
return a},
fH(a){var s=a.$S
if(s!=null){if(typeof s=="number")return A.ky(s)
return a.$S()}return null},
kC(a,b){var s
if(A.ha(b))if(a instanceof A.aq){s=A.fH(a)
if(s!=null)return s}return A.aV(a)},
aV(a){if(a instanceof A.d)return A.B(a)
if(Array.isArray(a))return A.aa(a)
return A.fz(J.ao(a))},
aa(a){var s=a[v.arrayRti],r=t.b
if(s==null)return r
if(s.constructor!==r.constructor)return r
return s},
B(a){var s=a.$ti
return s!=null?s:A.fz(a)},
fz(a){var s=a.constructor,r=s.$ccache
if(r!=null)return r
return A.jB(a,s)},
jB(a,b){var s=a instanceof A.aq?Object.getPrototypeOf(Object.getPrototypeOf(a)).constructor:b,r=A.jf(v.typeUniverse,s.name)
b.$ccache=r
return r},
ky(a){var s,r=v.types,q=r[a]
if(typeof q=="string"){s=A.eF(v.typeUniverse,q,!1)
r[a]=s
return s}return q},
hU(a){return A.a6(A.B(a))},
fD(a){var s
if(a instanceof A.aQ)return a.aW()
s=a instanceof A.aq?A.fH(a):null
if(s!=null)return s
if(t.dm.b(a))return J.bx(a).a
if(Array.isArray(a))return A.aa(a)
return A.aV(a)},
a6(a){var s=a.r
return s==null?a.r=new A.eE(a):s},
kv(a,b){var s,r,q=b,p=q.length
if(p===0)return t.bQ
if(0>=p)return A.b(q,0)
s=A.ci(v.typeUniverse,A.fD(q[0]),"@<0>")
for(r=1;r<p;++r){if(!(r<q.length))return A.b(q,r)
s=A.hw(v.typeUniverse,s,A.fD(q[r]))}return A.ci(v.typeUniverse,s,a)},
a1(a){return A.a6(A.eF(v.typeUniverse,a,!1))},
jA(a){var s=this
s.b=A.k8(s)
return s.b(a)},
k8(a){var s,r,q,p,o
if(a===t.K)return A.jK
if(A.aW(a))return A.jP
s=a.w
if(s===6)return A.jy
if(s===1)return A.hJ
if(s===7)return A.jF
r=A.k7(a)
if(r!=null)return r
if(s===8){q=a.x
if(a.y.every(A.aW)){a.f="$i"+q
if(q==="j")return A.jI
if(a===t.m)return A.jH
return A.jO}}else if(s===10){p=A.kr(a.x,a.y)
o=p==null?A.hJ:p
return o==null?A.a0(o):o}return A.jw},
k7(a){if(a.w===8){if(a===t.S)return A.cl
if(a===t.i||a===t.o)return A.jJ
if(a===t.N)return A.jN
if(a===t.y)return A.dc}return null},
jz(a){var s=this,r=A.jv
if(A.aW(s))r=A.jk
else if(s===t.K)r=A.a0
else if(A.bw(s)){r=A.jx
if(s===t.h6)r=A.jj
else if(s===t.c8)r=A.fv
else if(s===t.fQ)r=A.jh
else if(s===t.cg)r=A.hA
else if(s===t.I)r=A.ji
else if(s===t.bX)r=A.ft}else if(s===t.S)r=A.u
else if(s===t.N)r=A.al
else if(s===t.y)r=A.hz
else if(s===t.o)r=A.fu
else if(s===t.i)r=A.da
else if(s===t.m)r=A.a_
s.a=r
return s.a(a)},
jw(a){var s=this
if(a==null)return A.bw(s)
return A.kE(v.typeUniverse,A.kC(a,s),s)},
jy(a){if(a==null)return!0
return this.x.b(a)},
jO(a){var s,r=this
if(a==null)return A.bw(r)
s=r.f
if(a instanceof A.d)return!!a[s]
return!!J.ao(a)[s]},
jI(a){var s,r=this
if(a==null)return A.bw(r)
if(typeof a!="object")return!1
if(Array.isArray(a))return!0
s=r.f
if(a instanceof A.d)return!!a[s]
return!!J.ao(a)[s]},
jH(a){var s=this
if(a==null)return!1
if(typeof a=="object"){if(a instanceof A.d)return!!a[s.f]
return!0}if(typeof a=="function")return!0
return!1},
hI(a){if(typeof a=="object"){if(a instanceof A.d)return t.m.b(a)
return!0}if(typeof a=="function")return!0
return!1},
jv(a){var s=this
if(a==null){if(A.bw(s))return a}else if(s.b(a))return a
throw A.F(A.hC(a,s),new Error())},
jx(a){var s=this
if(a==null||s.b(a))return a
throw A.F(A.hC(a,s),new Error())},
hC(a,b){return new A.ce("TypeError: "+A.hk(a,A.O(b,null)))},
hk(a,b){return A.cB(a)+": type '"+A.O(A.fD(a),null)+"' is not a subtype of type '"+b+"'"},
Z(a,b){return new A.ce("TypeError: "+A.hk(a,b))},
jF(a){var s=this
return s.x.b(a)||A.fl(v.typeUniverse,s).b(a)},
jK(a){return a!=null},
a0(a){if(a!=null)return a
throw A.F(A.Z(a,"Object"),new Error())},
jP(a){return!0},
jk(a){return a},
hJ(a){return!1},
dc(a){return!0===a||!1===a},
hz(a){if(!0===a)return!0
if(!1===a)return!1
throw A.F(A.Z(a,"bool"),new Error())},
jh(a){if(!0===a)return!0
if(!1===a)return!1
if(a==null)return a
throw A.F(A.Z(a,"bool?"),new Error())},
da(a){if(typeof a=="number")return a
throw A.F(A.Z(a,"double"),new Error())},
ji(a){if(typeof a=="number")return a
if(a==null)return a
throw A.F(A.Z(a,"double?"),new Error())},
cl(a){return typeof a=="number"&&Math.floor(a)===a},
u(a){if(typeof a=="number"&&Math.floor(a)===a)return a
throw A.F(A.Z(a,"int"),new Error())},
jj(a){if(typeof a=="number"&&Math.floor(a)===a)return a
if(a==null)return a
throw A.F(A.Z(a,"int?"),new Error())},
jJ(a){return typeof a=="number"},
fu(a){if(typeof a=="number")return a
throw A.F(A.Z(a,"num"),new Error())},
hA(a){if(typeof a=="number")return a
if(a==null)return a
throw A.F(A.Z(a,"num?"),new Error())},
jN(a){return typeof a=="string"},
al(a){if(typeof a=="string")return a
throw A.F(A.Z(a,"String"),new Error())},
fv(a){if(typeof a=="string")return a
if(a==null)return a
throw A.F(A.Z(a,"String?"),new Error())},
a_(a){if(A.hI(a))return a
throw A.F(A.Z(a,"JSObject"),new Error())},
ft(a){if(a==null)return a
if(A.hI(a))return a
throw A.F(A.Z(a,"JSObject?"),new Error())},
hO(a,b){var s,r,q
for(s="",r="",q=0;q<a.length;++q,r=", ")s+=r+A.O(a[q],b)
return s},
k1(a,b){var s,r,q,p,o,n,m=a.x,l=a.y
if(""===m)return"("+A.hO(l,b)+")"
s=l.length
r=m.split(",")
q=r.length-s
for(p="(",o="",n=0;n<s;++n,o=", "){p+=o
if(q===0)p+="{"
p+=A.O(l[n],b)
if(q>=0)p+=" "+r[q];++q}return p+"})"},
hF(a3,a4,a5){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1=", ",a2=null
if(a5!=null){s=a5.length
if(a4==null)a4=A.i([],t.s)
else a2=a4.length
r=a4.length
for(q=s;q>0;--q)B.b.j(a4,"T"+(r+q))
for(p=t.X,o="<",n="",q=0;q<s;++q,n=a1){m=a4.length
l=m-1-q
if(!(l>=0))return A.b(a4,l)
o=o+n+a4[l]
k=a5[q]
j=k.w
if(!(j===2||j===3||j===4||j===5||k===p))o+=" extends "+A.O(k,a4)}o+=">"}else o=""
p=a3.x
i=a3.y
h=i.a
g=h.length
f=i.b
e=f.length
d=i.c
c=d.length
b=A.O(p,a4)
for(a="",a0="",q=0;q<g;++q,a0=a1)a+=a0+A.O(h[q],a4)
if(e>0){a+=a0+"["
for(a0="",q=0;q<e;++q,a0=a1)a+=a0+A.O(f[q],a4)
a+="]"}if(c>0){a+=a0+"{"
for(a0="",q=0;q<c;q+=3,a0=a1){a+=a0
if(d[q+1])a+="required "
a+=A.O(d[q+2],a4)+" "+d[q]}a+="}"}if(a2!=null){a4.toString
a4.length=a2}return o+"("+a+") => "+b},
O(a,b){var s,r,q,p,o,n,m,l=a.w
if(l===5)return"erased"
if(l===2)return"dynamic"
if(l===3)return"void"
if(l===1)return"Never"
if(l===4)return"any"
if(l===6){s=a.x
r=A.O(s,b)
q=s.w
return(q===11||q===12?"("+r+")":r)+"?"}if(l===7)return"FutureOr<"+A.O(a.x,b)+">"
if(l===8){p=A.kd(a.x)
o=a.y
return o.length>0?p+("<"+A.hO(o,b)+">"):p}if(l===10)return A.k1(a,b)
if(l===11)return A.hF(a,b,null)
if(l===12)return A.hF(a.x,b,a.y)
if(l===13){n=a.x
m=b.length
n=m-1-n
if(!(n>=0&&n<m))return A.b(b,n)
return b[n]}return"?"},
kd(a){var s=v.mangledGlobalNames[a]
if(s!=null)return s
return"minified:"+a},
jg(a,b){var s=a.tR[b]
while(typeof s=="string")s=a.tR[s]
return s},
jf(a,b){var s,r,q,p,o,n=a.eT,m=n[b]
if(m==null)return A.eF(a,b,!1)
else if(typeof m=="number"){s=m
r=A.ch(a,5,"#")
q=A.eH(s)
for(p=0;p<s;++p)q[p]=r
o=A.cg(a,b,q)
n[b]=o
return o}else return m},
je(a,b){return A.hx(a.tR,b)},
jd(a,b){return A.hx(a.eT,b)},
eF(a,b,c){var s,r=a.eC,q=r.get(b)
if(q!=null)return q
s=A.ho(A.hm(a,null,b,!1))
r.set(b,s)
return s},
ci(a,b,c){var s,r,q=b.z
if(q==null)q=b.z=new Map()
s=q.get(c)
if(s!=null)return s
r=A.ho(A.hm(a,b,c,!0))
q.set(c,r)
return r},
hw(a,b,c){var s,r,q,p=b.Q
if(p==null)p=b.Q=new Map()
s=c.as
r=p.get(s)
if(r!=null)return r
q=A.fr(a,b,c.w===9?c.y:[c])
p.set(s,q)
return q},
aA(a,b){b.a=A.jz
b.b=A.jA
return b},
ch(a,b,c){var s,r,q=a.eC.get(c)
if(q!=null)return q
s=new A.a3(null,null)
s.w=b
s.as=c
r=A.aA(a,s)
a.eC.set(c,r)
return r},
hu(a,b,c){var s,r=b.as+"?",q=a.eC.get(r)
if(q!=null)return q
s=A.jb(a,b,r,c)
a.eC.set(r,s)
return s},
jb(a,b,c,d){var s,r,q
if(d){s=b.w
r=!0
if(!A.aW(b))if(!(b===t.P||b===t.T))if(s!==6)r=s===7&&A.bw(b.x)
if(r)return b
else if(s===1)return t.P}q=new A.a3(null,null)
q.w=6
q.x=b
q.as=c
return A.aA(a,q)},
ht(a,b,c){var s,r=b.as+"/",q=a.eC.get(r)
if(q!=null)return q
s=A.j9(a,b,r,c)
a.eC.set(r,s)
return s},
j9(a,b,c,d){var s,r
if(d){s=b.w
if(A.aW(b)||b===t.K)return b
else if(s===1)return A.cg(a,"L",[b])
else if(b===t.P||b===t.T)return t.eH}r=new A.a3(null,null)
r.w=7
r.x=b
r.as=c
return A.aA(a,r)},
jc(a,b){var s,r,q=""+b+"^",p=a.eC.get(q)
if(p!=null)return p
s=new A.a3(null,null)
s.w=13
s.x=b
s.as=q
r=A.aA(a,s)
a.eC.set(q,r)
return r},
cf(a){var s,r,q,p=a.length
for(s="",r="",q=0;q<p;++q,r=",")s+=r+a[q].as
return s},
j8(a){var s,r,q,p,o,n=a.length
for(s="",r="",q=0;q<n;q+=3,r=","){p=a[q]
o=a[q+1]?"!":":"
s+=r+p+o+a[q+2].as}return s},
cg(a,b,c){var s,r,q,p=b
if(c.length>0)p+="<"+A.cf(c)+">"
s=a.eC.get(p)
if(s!=null)return s
r=new A.a3(null,null)
r.w=8
r.x=b
r.y=c
if(c.length>0)r.c=c[0]
r.as=p
q=A.aA(a,r)
a.eC.set(p,q)
return q},
fr(a,b,c){var s,r,q,p,o,n
if(b.w===9){s=b.x
r=b.y.concat(c)}else{r=c
s=b}q=s.as+(";<"+A.cf(r)+">")
p=a.eC.get(q)
if(p!=null)return p
o=new A.a3(null,null)
o.w=9
o.x=s
o.y=r
o.as=q
n=A.aA(a,o)
a.eC.set(q,n)
return n},
hv(a,b,c){var s,r,q="+"+(b+"("+A.cf(c)+")"),p=a.eC.get(q)
if(p!=null)return p
s=new A.a3(null,null)
s.w=10
s.x=b
s.y=c
s.as=q
r=A.aA(a,s)
a.eC.set(q,r)
return r},
hs(a,b,c){var s,r,q,p,o,n=b.as,m=c.a,l=m.length,k=c.b,j=k.length,i=c.c,h=i.length,g="("+A.cf(m)
if(j>0){s=l>0?",":""
g+=s+"["+A.cf(k)+"]"}if(h>0){s=l>0?",":""
g+=s+"{"+A.j8(i)+"}"}r=n+(g+")")
q=a.eC.get(r)
if(q!=null)return q
p=new A.a3(null,null)
p.w=11
p.x=b
p.y=c
p.as=r
o=A.aA(a,p)
a.eC.set(r,o)
return o},
fs(a,b,c,d){var s,r=b.as+("<"+A.cf(c)+">"),q=a.eC.get(r)
if(q!=null)return q
s=A.ja(a,b,c,r,d)
a.eC.set(r,s)
return s},
ja(a,b,c,d,e){var s,r,q,p,o,n,m,l
if(e){s=c.length
r=A.eH(s)
for(q=0,p=0;p<s;++p){o=c[p]
if(o.w===1){r[p]=o;++q}}if(q>0){n=A.aS(a,b,r,0)
m=A.br(a,c,r,0)
return A.fs(a,n,m,c!==m)}}l=new A.a3(null,null)
l.w=12
l.x=b
l.y=c
l.as=d
return A.aA(a,l)},
hm(a,b,c,d){return{u:a,e:b,r:c,s:[],p:0,n:d}},
ho(a){var s,r,q,p,o,n,m,l=a.r,k=a.s
for(s=l.length,r=0;r<s;){q=l.charCodeAt(r)
if(q>=48&&q<=57)r=A.j2(r+1,q,l,k)
else if((((q|32)>>>0)-97&65535)<26||q===95||q===36||q===124)r=A.hn(a,r,l,k,!1)
else if(q===46)r=A.hn(a,r,l,k,!0)
else{++r
switch(q){case 44:break
case 58:k.push(!1)
break
case 33:k.push(!0)
break
case 59:k.push(A.aP(a.u,a.e,k.pop()))
break
case 94:k.push(A.jc(a.u,k.pop()))
break
case 35:k.push(A.ch(a.u,5,"#"))
break
case 64:k.push(A.ch(a.u,2,"@"))
break
case 126:k.push(A.ch(a.u,3,"~"))
break
case 60:k.push(a.p)
a.p=k.length
break
case 62:A.j4(a,k)
break
case 38:A.j3(a,k)
break
case 63:p=a.u
k.push(A.hu(p,A.aP(p,a.e,k.pop()),a.n))
break
case 47:p=a.u
k.push(A.ht(p,A.aP(p,a.e,k.pop()),a.n))
break
case 40:k.push(-3)
k.push(a.p)
a.p=k.length
break
case 41:A.j1(a,k)
break
case 91:k.push(a.p)
a.p=k.length
break
case 93:o=k.splice(a.p)
A.hp(a.u,a.e,o)
a.p=k.pop()
k.push(o)
k.push(-1)
break
case 123:k.push(a.p)
a.p=k.length
break
case 125:o=k.splice(a.p)
A.j6(a.u,a.e,o)
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
return A.aP(a.u,a.e,m)},
j2(a,b,c,d){var s,r,q=b-48
for(s=c.length;a<s;++a){r=c.charCodeAt(a)
if(!(r>=48&&r<=57))break
q=q*10+(r-48)}d.push(q)
return a},
hn(a,b,c,d,e){var s,r,q,p,o,n,m=b+1
for(s=c.length;m<s;++m){r=c.charCodeAt(m)
if(r===46){if(e)break
e=!0}else{if(!((((r|32)>>>0)-97&65535)<26||r===95||r===36||r===124))q=r>=48&&r<=57
else q=!0
if(!q)break}}p=c.substring(b,m)
if(e){s=a.u
o=a.e
if(o.w===9)o=o.x
n=A.jg(s,o.x)[p]
if(n==null)A.D('No "'+p+'" in "'+A.iO(o)+'"')
d.push(A.ci(s,o,n))}else d.push(p)
return m},
j4(a,b){var s,r=a.u,q=A.hl(a,b),p=b.pop()
if(typeof p=="string")b.push(A.cg(r,p,q))
else{s=A.aP(r,a.e,p)
switch(s.w){case 11:b.push(A.fs(r,s,q,a.n))
break
default:b.push(A.fr(r,s,q))
break}}},
j1(a,b){var s,r,q,p=a.u,o=b.pop(),n=null,m=null
if(typeof o=="number")switch(o){case-1:n=b.pop()
break
case-2:m=b.pop()
break
default:b.push(o)
break}else b.push(o)
s=A.hl(a,b)
o=b.pop()
switch(o){case-3:o=b.pop()
if(n==null)n=p.sEA
if(m==null)m=p.sEA
r=A.aP(p,a.e,o)
q=new A.d3()
q.a=s
q.b=n
q.c=m
b.push(A.hs(p,r,q))
return
case-4:b.push(A.hv(p,b.pop(),s))
return
default:throw A.a(A.ct("Unexpected state under `()`: "+A.o(o)))}},
j3(a,b){var s=b.pop()
if(0===s){b.push(A.ch(a.u,1,"0&"))
return}if(1===s){b.push(A.ch(a.u,4,"1&"))
return}throw A.a(A.ct("Unexpected extended operation "+A.o(s)))},
hl(a,b){var s=b.splice(a.p)
A.hp(a.u,a.e,s)
a.p=b.pop()
return s},
aP(a,b,c){if(typeof c=="string")return A.cg(a,c,a.sEA)
else if(typeof c=="number"){b.toString
return A.j5(a,b,c)}else return c},
hp(a,b,c){var s,r=c.length
for(s=0;s<r;++s)c[s]=A.aP(a,b,c[s])},
j6(a,b,c){var s,r=c.length
for(s=2;s<r;s+=3)c[s]=A.aP(a,b,c[s])},
j5(a,b,c){var s,r,q=b.w
if(q===9){if(c===0)return b.x
s=b.y
r=s.length
if(c<=r)return s[c-1]
c-=r
b=b.x
q=b.w}else if(c===0)return b
if(q!==8)throw A.a(A.ct("Indexed base must be an interface type"))
s=b.y
if(c<=s.length)return s[c-1]
throw A.a(A.ct("Bad index "+c+" for "+b.i(0)))},
kE(a,b,c){var s,r=b.d
if(r==null)r=b.d=new Map()
s=r.get(c)
if(s==null){s=A.C(a,b,null,c,null)
r.set(c,s)}return s},
C(a,b,c,d,e){var s,r,q,p,o,n,m,l,k,j,i
if(b===d)return!0
if(A.aW(d))return!0
s=b.w
if(s===4)return!0
if(A.aW(b))return!1
if(b.w===1)return!0
r=s===13
if(r)if(A.C(a,c[b.x],c,d,e))return!0
q=d.w
p=t.P
if(b===p||b===t.T){if(q===7)return A.C(a,b,c,d.x,e)
return d===p||d===t.T||q===6}if(d===t.K){if(s===7)return A.C(a,b.x,c,d,e)
return s!==6}if(s===7){if(!A.C(a,b.x,c,d,e))return!1
return A.C(a,A.fl(a,b),c,d,e)}if(s===6)return A.C(a,p,c,d,e)&&A.C(a,b.x,c,d,e)
if(q===7){if(A.C(a,b,c,d.x,e))return!0
return A.C(a,b,c,A.fl(a,d),e)}if(q===6)return A.C(a,b,c,p,e)||A.C(a,b,c,d.x,e)
if(r)return!1
p=s!==11
if((!p||s===12)&&d===t.Z)return!0
o=s===10
if(o&&d===t.fl)return!0
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
if(!A.C(a,j,c,i,e)||!A.C(a,i,e,j,c))return!1}return A.hH(a,b.x,c,d.x,e)}if(q===11){if(b===t.g)return!0
if(p)return!1
return A.hH(a,b,c,d,e)}if(s===8){if(q!==8)return!1
return A.jG(a,b,c,d,e)}if(o&&q===10)return A.jM(a,b,c,d,e)
return!1},
hH(a3,a4,a5,a6,a7){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2
if(!A.C(a3,a4.x,a5,a6.x,a7))return!1
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
if(!A.C(a3,p[h],a7,g,a5))return!1}for(h=0;h<m;++h){g=l[h]
if(!A.C(a3,p[o+h],a7,g,a5))return!1}for(h=0;h<i;++h){g=l[m+h]
if(!A.C(a3,k[h],a7,g,a5))return!1}f=s.c
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
if(!A.C(a3,e[a+2],a7,g,a5))return!1
break}}while(b<d){if(f[b+1])return!1
b+=3}return!0},
jG(a,b,c,d,e){var s,r,q,p,o,n=b.x,m=d.x
while(n!==m){s=a.tR[n]
if(s==null)return!1
if(typeof s=="string"){n=s
continue}r=s[m]
if(r==null)return!1
q=r.length
p=q>0?new Array(q):v.typeUniverse.sEA
for(o=0;o<q;++o)p[o]=A.ci(a,b,r[o])
return A.hy(a,p,null,c,d.y,e)}return A.hy(a,b.y,null,c,d.y,e)},
hy(a,b,c,d,e,f){var s,r=b.length
for(s=0;s<r;++s)if(!A.C(a,b[s],d,e[s],f))return!1
return!0},
jM(a,b,c,d,e){var s,r=b.y,q=d.y,p=r.length
if(p!==q.length)return!1
if(b.x!==d.x)return!1
for(s=0;s<p;++s)if(!A.C(a,r[s],c,q[s],e))return!1
return!0},
bw(a){var s=a.w,r=!0
if(!(a===t.P||a===t.T))if(!A.aW(a))if(s!==6)r=s===7&&A.bw(a.x)
return r},
aW(a){var s=a.w
return s===2||s===3||s===4||s===5||a===t.X},
hx(a,b){var s,r,q=Object.keys(b),p=q.length
for(s=0;s<p;++s){r=q[s]
a[r]=b[r]}},
eH(a){return a>0?new Array(a):v.typeUniverse.sEA},
a3:function a3(a,b){var _=this
_.a=a
_.b=b
_.r=_.f=_.d=_.c=null
_.w=0
_.as=_.Q=_.z=_.y=_.x=null},
d3:function d3(){this.c=this.b=this.a=null},
eE:function eE(a){this.a=a},
d2:function d2(){},
ce:function ce(a){this.a=a},
iU(){var s,r,q
if(self.scheduleImmediate!=null)return A.kg()
if(self.MutationObserver!=null&&self.document!=null){s={}
r=self.document.createElement("div")
q=self.document.createElement("span")
s.a=null
new self.MutationObserver(A.bt(new A.e4(s),1)).observe(r,{childList:true})
return new A.e3(s,r,q)}else if(self.setImmediate!=null)return A.kh()
return A.ki()},
iV(a){self.scheduleImmediate(A.bt(new A.e5(t.M.a(a)),0))},
iW(a){self.setImmediate(A.bt(new A.e6(t.M.a(a)),0))},
iX(a){A.fm(B.as,t.M.a(a))},
fm(a,b){return A.j7(a.a/1000|0,b)},
j7(a,b){var s=new A.eC()
s.by(a,b)
return s},
z(a){return new A.c_(new A.f($.h,a.h("f<0>")),a.h("c_<0>"))},
y(a,b){a.$2(0,null)
b.b=!0
return b.a},
J(a,b){A.jo(a,b)},
x(a,b){b.a7(a)},
w(a,b){b.az(A.P(a),A.S(a))},
jo(a,b){var s,r,q=new A.eM(b),p=new A.eN(b)
if(a instanceof A.f)a.b6(q,p,t.z)
else{s=t.z
if(a instanceof A.f)a.W(q,p,s)
else{r=new A.f($.h,t._)
r.a=8
r.c=a
r.b6(q,p,s)}}},
A(a){var s=function(b,c){return function(d,e){while(true){try{b(d,e)
break}catch(r){e=r
d=c}}}}(a,1)
return $.h.aD(new A.eU(s),t.H,t.S,t.z)},
hr(a,b,c){return 0},
cu(a){var s
if(t.C.b(a)){s=a.gP()
if(s!=null)return s}return B.f},
ir(a,b){var s,r,q,p,o,n,m,l=null
try{l=a.$0()}catch(q){s=A.P(q)
r=A.S(q)
p=new A.f($.h,b.h("f<0>"))
o=s
n=r
m=A.hG(o,n)
o=new A.G(o,n==null?A.cu(o):n)
p.S(o)
return p}return b.h("L<0>").b(l)?l:A.ed(l,b)},
fY(a,b){var s
if(!b.b(null))throw A.a(A.aC(null,"computation","The type parameter is not nullable"))
s=new A.f($.h,b.h("f<0>"))
A.hf(a,new A.ds(null,s,b))
return s},
hG(a,b){if($.h===B.c)return null
return null},
jC(a,b){if($.h!==B.c)A.hG(a,b)
if(b==null)if(t.C.b(a)){b=a.gP()
if(b==null){A.h8(a,B.f)
b=B.f}}else b=B.f
else if(t.C.b(a))A.h8(a,b)
return new A.G(a,b)},
ed(a,b){var s=new A.f($.h,b.h("f<0>"))
b.a(a)
s.a=8
s.c=a
return s},
eh(a,b,c){var s,r,q,p,o={},n=o.a=a
for(s=t._;r=n.a,(r&4)!==0;n=a){a=s.a(n.c)
o.a=a}if(n===b){s=A.iP()
b.S(new A.G(new A.a2(!0,n,null,"Cannot complete a future with itself"),s))
return}q=b.a&1
s=n.a=r|q
if((s&24)===0){p=t.F.a(b.c)
b.a=b.a&1|4
b.c=n
n.b1(p)
return}if(!c)if(b.c==null)n=(s&16)===0||q!==0
else n=!1
else n=!0
if(n){p=b.T()
b.a1(o.a)
A.aO(b,p)
return}b.a^=2
A.bq(null,null,b.b,t.M.a(new A.ei(o,b)))},
aO(a,b){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d={},c=d.a=a
for(s=t.n,r=t.F;;){q={}
p=c.a
o=(p&16)===0
n=!o
if(b==null){if(n&&(p&1)===0){m=s.a(c.c)
A.dd(m.a,m.b)}return}q.a=b
l=b.a
for(c=b;l!=null;c=l,l=k){c.a=null
A.aO(d.a,c)
q.a=l
k=l.a}p=d.a
j=p.c
q.b=n
q.c=j
if(o){i=c.c
i=(i&1)!==0||(i&15)===8}else i=!0
if(i){h=c.b.b
if(n){p=p.b===h
p=!(p||p)}else p=!1
if(p){s.a(j)
A.dd(j.a,j.b)
return}g=$.h
if(g!==h)$.h=h
else g=null
c=c.c
if((c&15)===8)new A.em(q,d,n).$0()
else if(o){if((c&1)!==0)new A.el(q,j).$0()}else if((c&2)!==0)new A.ek(d,q).$0()
if(g!=null)$.h=g
c=q.c
if(c instanceof A.f){p=q.a.$ti
p=p.h("L<2>").b(c)||!p.y[1].b(c)}else p=!1
if(p){f=q.a.b
if((c.a&24)!==0){e=r.a(f.c)
f.c=null
b=f.a2(e)
f.a=c.a&30|f.a&1
f.c=c.c
d.a=c
continue}else A.eh(c,f,!0)
return}}f=q.a.b
e=r.a(f.c)
f.c=null
b=f.a2(e)
c=q.b
p=q.c
if(!c){f.$ti.c.a(p)
f.a=8
f.c=p}else{s.a(p)
f.a=f.a&1|16
f.c=p}d.a=f
c=f}},
k2(a,b){var s
if(t.Q.b(a))return b.aD(a,t.z,t.K,t.l)
s=t.v
if(s.b(a))return s.a(a)
throw A.a(A.aC(a,"onError",u.c))},
jR(){var s,r
for(s=$.bp;s!=null;s=$.bp){$.cn=null
r=s.b
$.bp=r
if(r==null)$.cm=null
s.a.$0()}},
k9(){$.fA=!0
try{A.jR()}finally{$.cn=null
$.fA=!1
if($.bp!=null)$.fP().$1(A.hS())}},
hP(a){var s=new A.cX(a),r=$.cm
if(r==null){$.bp=$.cm=s
if(!$.fA)$.fP().$1(A.hS())}else $.cm=r.b=s},
k6(a){var s,r,q,p=$.bp
if(p==null){A.hP(a)
$.cn=$.cm
return}s=new A.cX(a)
r=$.cn
if(r==null){s.b=p
$.bp=$.cn=s}else{q=r.b
s.b=q
$.cn=r.b=s
if(q==null)$.cm=s}},
kN(a){var s=null,r=$.h
if(B.c===r){A.bq(s,s,B.c,a)
return}A.bq(s,s,r,t.M.a(r.au(a)))},
kV(a,b){A.fF(a,"stream",t.K)
return new A.d6(b.h("d6<0>"))},
hc(a){var s=null
return new A.bi(s,s,s,s,a.h("bi<0>"))},
fC(a){return},
iY(a,b){if(b==null)b=A.kj()
if(t.da.b(b))return a.aD(b,t.z,t.K,t.l)
if(t.d5.b(b))return t.v.a(b)
throw A.a(A.by("handleError callback must take either an Object (the error), or both an Object (the error) and a StackTrace.",null))},
jS(a,b){A.dd(A.a0(a),t.l.a(b))},
hf(a,b){var s=$.h
if(s===B.c)return A.fm(a,t.M.a(b))
return A.fm(a,t.M.a(s.au(b)))},
dd(a,b){A.k6(new A.eR(a,b))},
hM(a,b,c,d,e){var s,r=$.h
if(r===c)return d.$0()
$.h=c
s=r
try{r=d.$0()
return r}finally{$.h=s}},
hN(a,b,c,d,e,f,g){var s,r=$.h
if(r===c)return d.$1(e)
$.h=c
s=r
try{r=d.$1(e)
return r}finally{$.h=s}},
k4(a,b,c,d,e,f,g,h,i){var s,r=$.h
if(r===c)return d.$2(e,f)
$.h=c
s=r
try{r=d.$2(e,f)
return r}finally{$.h=s}},
bq(a,b,c,d){t.M.a(d)
if(B.c!==c){d=c.au(d)
d=d}A.hP(d)},
e4:function e4(a){this.a=a},
e3:function e3(a,b,c){this.a=a
this.b=b
this.c=c},
e5:function e5(a){this.a=a},
e6:function e6(a){this.a=a},
eC:function eC(){this.b=null},
eD:function eD(a,b){this.a=a
this.b=b},
c_:function c_(a,b){this.a=a
this.b=!1
this.$ti=b},
eM:function eM(a){this.a=a},
eN:function eN(a){this.a=a},
eU:function eU(a){this.a=a},
E:function E(a,b){var _=this
_.a=a
_.e=_.d=_.c=_.b=null
_.$ti=b},
bn:function bn(a,b){this.a=a
this.$ti=b},
G:function G(a,b){this.a=a
this.b=b},
ds:function ds(a,b,c){this.a=a
this.b=b
this.c=c},
c1:function c1(){},
ai:function ai(a,b){this.a=a
this.$ti=b},
aj:function aj(a,b,c,d,e){var _=this
_.a=null
_.b=a
_.c=b
_.d=c
_.e=d
_.$ti=e},
f:function f(a,b){var _=this
_.a=0
_.b=a
_.c=null
_.$ti=b},
ee:function ee(a,b){this.a=a
this.b=b},
ej:function ej(a,b){this.a=a
this.b=b},
ei:function ei(a,b){this.a=a
this.b=b},
eg:function eg(a,b){this.a=a
this.b=b},
ef:function ef(a,b){this.a=a
this.b=b},
em:function em(a,b,c){this.a=a
this.b=b
this.c=c},
en:function en(a,b){this.a=a
this.b=b},
eo:function eo(a){this.a=a},
el:function el(a,b){this.a=a
this.b=b},
ek:function ek(a,b){this.a=a
this.b=b},
ep:function ep(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
eq:function eq(a,b,c){this.a=a
this.b=b
this.c=c},
er:function er(a,b){this.a=a
this.b=b},
cX:function cX(a){this.a=a
this.b=null},
bU:function bU(){},
dP:function dP(a,b){this.a=a
this.b=b},
dQ:function dQ(a,b){this.a=a
this.b=b},
cb:function cb(){},
eB:function eB(a){this.a=a},
eA:function eA(a){this.a=a},
cY:function cY(){},
bi:function bi(a,b,c,d,e){var _=this
_.a=null
_.b=0
_.c=null
_.d=a
_.e=b
_.f=c
_.r=d
_.$ti=e},
bj:function bj(a,b){this.a=a
this.$ti=b},
bk:function bk(a,b,c,d,e,f){var _=this
_.w=a
_.a=b
_.c=c
_.d=d
_.e=e
_.r=_.f=null
_.$ti=f},
c0:function c0(){},
e7:function e7(a){this.a=a},
cd:function cd(){},
az:function az(){},
aM:function aM(a,b){this.b=a
this.a=null
this.$ti=b},
d0:function d0(){},
a5:function a5(a){var _=this
_.a=0
_.c=_.b=null
_.$ti=a},
ex:function ex(a,b){this.a=a
this.b=b},
d6:function d6(a){this.$ti=a},
ck:function ck(){},
d5:function d5(){},
ez:function ez(a,b){this.a=a
this.b=b},
eR:function eR(a,b){this.a=a
this.b=b},
fi(a,b,c){return b.h("@<0>").C(c).h("h_<1,2>").a(A.kw(a,new A.aF(b.h("@<0>").C(c).h("aF<1,2>"))))},
h0(a,b){return new A.aF(a.h("@<0>").C(b).h("aF<1,2>"))},
iy(a){return new A.c2(a.h("c2<0>"))},
fq(){var s=Object.create(null)
s["<non-identifier-key>"]=s
delete s["<non-identifier-key>"]
return s},
fk(a){var s,r
if(A.fL(a))return"{...}"
s=new A.bf("")
try{r={}
B.b.j($.Y,a)
s.a+="{"
r.a=!0
a.N(0,new A.dA(r,s))
s.a+="}"}finally{if(0>=$.Y.length)return A.b($.Y,-1)
$.Y.pop()}r=s.a
return r.charCodeAt(0)==0?r:r},
c2:function c2(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
d4:function d4(a){this.a=a
this.b=null},
c3:function c3(a,b,c){var _=this
_.a=a
_.b=b
_.d=_.c=null
_.$ti=c},
k:function k(){},
bL:function bL(){},
dA:function dA(a,b){this.a=a
this.b=b},
be:function be(){},
c9:function c9(){},
fZ(a,b,c){return new A.bJ(a,b)},
jt(a){return a.bo()},
j_(a,b){return new A.et(a,[],A.kq())},
j0(a,b,c){var s,r=new A.bf(""),q=A.j_(r,b)
q.ab(a)
s=r.a
return s.charCodeAt(0)==0?s:s},
cy:function cy(){},
cA:function cA(){},
bJ:function bJ(a,b){this.a=a
this.b=b},
cK:function cK(a,b){this.a=a
this.b=b},
cJ:function cJ(){},
dx:function dx(a){this.b=a},
eu:function eu(){},
ev:function ev(a,b){this.a=a
this.b=b},
et:function et(a,b,c){this.c=a
this.a=b
this.b=c},
dX:function dX(){},
eG:function eG(a){this.b=0
this.c=a},
ip(a,b){a=A.F(a,new Error())
if(a==null)a=A.a0(a)
a.stack=b.i(0)
throw a},
aH(a,b,c,d){var s,r=J.iw(a,d)
if(a!==0&&b!=null)for(s=0;s<a;++s)r[s]=b
return r},
fj(a,b,c){var s,r,q=A.i([],c.h("p<0>"))
for(s=a.length,r=0;r<a.length;a.length===s||(0,A.cq)(a),++r)B.b.j(q,c.a(a[r]))
if(b)return q
q.$flags=1
return q},
h1(a,b){var s,r
if(Array.isArray(a))return A.i(a.slice(0),b.h("p<0>"))
s=A.i([],b.h("p<0>"))
for(r=J.cr(a);r.n();)B.b.j(s,r.gA())
return s},
he(a){var s,r
A.h9(0,"start")
s=a
r=s.length
return A.iM(r<r?s.slice(0,r):s)},
hd(a,b,c){var s=J.cr(b)
if(!s.n())return a
if(c.length===0){do a+=A.o(s.gA())
while(s.n())}else{a+=A.o(s.gA())
while(s.n())a=a+c+A.o(s.gA())}return a},
iP(){return A.S(new Error())},
cB(a){if(typeof a=="number"||A.dc(a)||a==null)return J.aY(a)
if(typeof a=="string")return JSON.stringify(a)
return A.h7(a)},
iq(a,b){A.fF(a,"error",t.K)
A.fF(b,"stackTrace",t.l)
A.ip(a,b)},
ct(a){return new A.cs(a)},
by(a,b){return new A.a2(!1,null,b,a)},
aC(a,b,c){return new A.a2(!0,a,b,c)},
ad(a,b,c,d,e){return new A.bR(b,c,!0,a,d,"Invalid value")},
cO(a,b,c){if(0>a||a>c)throw A.a(A.ad(a,0,c,"start",null))
if(b!=null){if(a>b||b>c)throw A.a(A.ad(b,a,c,"end",null))
return b}return c},
h9(a,b){if(a<0)throw A.a(A.ad(a,0,null,b,null))
return a},
is(a,b,c,d){return new A.cD(b,!0,a,d,"Index out of range")},
bY(a){return new A.bX(a)},
hh(a){return new A.cT(a)},
a9(a){return new A.ay(a)},
b_(a){return new A.cz(a)},
fe(a){return new A.cC(a)},
iu(a,b,c){var s,r
if(A.fL(a)){if(b==="("&&c===")")return"(...)"
return b+"..."+c}s=A.i([],t.s)
B.b.j($.Y,a)
try{A.jQ(a,s)}finally{if(0>=$.Y.length)return A.b($.Y,-1)
$.Y.pop()}r=A.hd(b,t.hf.a(s),", ")+c
return r.charCodeAt(0)==0?r:r},
ff(a,b,c){var s,r
if(A.fL(a))return b+"..."+c
s=new A.bf(b)
B.b.j($.Y,a)
try{r=s
r.a=A.hd(r.a,a,", ")}finally{if(0>=$.Y.length)return A.b($.Y,-1)
$.Y.pop()}s.a+=c
r=s.a
return r.charCodeAt(0)==0?r:r},
jQ(a,b){var s,r,q,p,o,n,m,l=a.gK(a),k=0,j=0
for(;;){if(!(k<80||j<3))break
if(!l.n())return
s=A.o(l.gA())
B.b.j(b,s)
k+=s.length+2;++j}if(!l.n()){if(j<=5)return
if(0>=b.length)return A.b(b,-1)
r=b.pop()
if(0>=b.length)return A.b(b,-1)
q=b.pop()}else{p=l.gA();++j
if(!l.n()){if(j<=4){B.b.j(b,A.o(p))
return}r=A.o(p)
if(0>=b.length)return A.b(b,-1)
q=b.pop()
k+=r.length+2}else{o=l.gA();++j
for(;l.n();p=o,o=n){n=l.gA();++j
if(j>100){for(;;){if(!(k>75&&j>3))break
if(0>=b.length)return A.b(b,-1)
k-=b.pop().length+2;--j}B.b.j(b,"...")
return}}q=A.o(p)
r=A.o(o)
k+=r.length+q.length+4}}if(j>b.length+2){k+=5
m="..."}else m=null
for(;;){if(!(k>80&&b.length>3))break
if(0>=b.length)return A.b(b,-1)
k-=b.pop().length+2
if(m==null){k+=5
m="..."}}if(m!=null)B.b.j(b,m)
B.b.j(b,q)
B.b.j(b,r)},
h3(a,b,c,d,e){var s
if(B.e===c){s=B.a.gp(a)
b=J.T(b)
return A.dR(A.X(A.X($.dh(),s),b))}if(B.e===d){s=B.a.gp(a)
b=J.T(b)
c=J.T(c)
return A.dR(A.X(A.X(A.X($.dh(),s),b),c))}if(B.e===e){s=B.a.gp(a)
b=J.T(b)
c=J.T(c)
d=J.T(d)
return A.dR(A.X(A.X(A.X(A.X($.dh(),s),b),c),d))}s=B.a.gp(a)
b=J.T(b)
c=J.T(c)
d=J.T(d)
e=J.T(e)
e=A.dR(A.X(A.X(A.X(A.X(A.X($.dh(),s),b),c),d),e))
return e},
b1:function b1(a){this.a=a},
eb:function eb(){},
n:function n(){},
cs:function cs(a){this.a=a},
af:function af(){},
a2:function a2(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
bR:function bR(a,b,c,d,e,f){var _=this
_.e=a
_.f=b
_.a=c
_.b=d
_.c=e
_.d=f},
cD:function cD(a,b,c,d,e){var _=this
_.f=a
_.a=b
_.b=c
_.c=d
_.d=e},
bX:function bX(a){this.a=a},
cT:function cT(a){this.a=a},
ay:function ay(a){this.a=a},
cz:function cz(a){this.a=a},
cL:function cL(){},
bT:function bT(){},
ec:function ec(a){this.a=a},
cC:function cC(a){this.a=a},
e:function e(){},
r:function r(){},
d:function d(){},
d7:function d7(){},
bf:function bf(a){this.a=a},
iv(a,b){var s,r,q,p,o
if(b.length===0)return!1
s=b.split(".")
r=v.G
for(q=s.length,p=0;p<q;++p,r=o){o=r[s[p]]
A.ft(o)
if(o==null)return!1}return a instanceof t.g.a(r)},
dH:function dH(a){this.a=a},
fy(a){var s
if(typeof a=="function")throw A.a(A.by("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d){return b(c,d,arguments.length)}}(A.jp,a)
s[$.fO()]=a
return s},
jp(a,b,c){t.Z.a(a)
if(A.u(c)>=1)return a.$1(b)
return a.$0()},
ko(a,b,c){var s,r
if(b==null)return c.a(new a())
if(b instanceof Array)switch(b.length){case 0:return c.a(new a())
case 1:return c.a(new a(b[0]))
case 2:return c.a(new a(b[0],b[1]))
case 3:return c.a(new a(b[0],b[1],b[2]))
case 4:return c.a(new a(b[0],b[1],b[2],b[3]))}s=[null]
B.b.c_(s,b)
r=a.bind.apply(a,s)
String(r)
return c.a(new r())},
kK(a,b){var s=new A.f($.h,b.h("f<0>")),r=new A.ai(s,b.h("ai<0>"))
a.then(A.bt(new A.f7(r,b),1),A.bt(new A.f8(r),1))
return s},
f7:function f7(a,b){this.a=a
this.b=b},
f8:function f8(a){this.a=a},
eP(a,b){var s,r,q,p,o,n,m,l,k
if(b+7>a.byteLength)return null
s=a.getUint8(b+1)
if(!(a.getUint8(b)===255&&(s&246)===240))return null
r=(s&1)===1?7:9
q=a.getUint8(b+2)
p=a.getUint8(b+3)
o=a.getUint8(b+4)
n=a.getUint8(b+5)
m=B.a.F(q,2)
l=B.a.F(p,6)
k=((p&3)<<11|o<<3|B.a.F(n,5)&7)>>>0
if(k<r)return null
return new A.e2(k,m&15,(q&1)<<2|l&3,r)},
k3(a,b){var s,r=b+65536,q=a.byteLength
if(r<q)q=r
for(s=b;s+7<=q;++s)if(A.jr(a,s))return s
return-1},
jr(a,b){var s,r,q=A.eP(a,b)
if(q==null)return!1
s=b+q.a
r=a.byteLength
if(s>r)return!1
if(s+7>r)return!0
return A.eP(a,s)!=null},
fS(a){var s=A.cp(a,0),r=a.length,q=0
for(;;){if(!(s>0&&q+s<=r))break
q+=s
s=A.cp(a,q)}if(q>0)for(;;){if(!(q<r&&a[q]===0))break;++q}return q},
e2:function e2(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
dk:function dk(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=0
_.r=!1
_.w=f},
fK(a,b){return a===255&&(b&224)===224&&(b&24)!==8&&(b&6)===2},
eQ(a,b){var s,r,q,p,o,n,m,l,k,j,i,h,g=null,f=a.length
if(b+4>f)return g
s=b+1
if(!(s>=0&&s<f))return A.b(a,s)
r=a[s]
if(!(b>=0&&b<f))return A.b(a,b)
if(!A.fK(a[b],r))return g
s=b+2
if(!(s<f))return A.b(a,s)
q=a[s]
p=r>>>3&3
o=q>>>4&15
n=q>>>2&3
if(n===3)return g
m=p===3
s=m?B.aG:B.aB
if(!(o<s.length))return A.b(s,o)
l=s[o]
if(l===0)return g
A:{if(3===p){if(!(n<3))return A.b(B.J,n)
s=B.J[n]
break A}if(2===p){if(!(n<3))return A.b(B.I,n)
s=B.I[n]
break A}if(!(n<3))return A.b(B.H,n)
s=B.H[n]
break A}k=l*1000
j=q>>>1&1
i=m?B.a.u(144*k,s)+j:B.a.u(72*k,s)+j
if(i<=4)return g
h=b+3
if(!(h<f))return A.b(a,h)
f=(a[h]>>>6&3)===3?1:2
h=m?1152:576
return new A.ew(p,i,s,f,h,(r&1)===0)},
jE(a,b){var s,r,q=a.length
if(b+4>q)return!1
if(!(b<q))return A.b(a,b)
s=a[b]
r=b+1
if(!(r<q))return A.b(a,r)
if(!A.fK(s,a[r]))return!1
s=b+2
if(!(s<q))return A.b(a,s)
s=a[s]
return(s>>>4&15)===0&&(s>>>2&3)!==3},
cp(a,b){var s,r,q,p,o,n,m
if(b<0||b+10>a.length)return 0
s=a.length
if(!(b>=0&&b<s))return A.b(a,b)
r=a[b]
q=b+1
if(!(q<s))return A.b(a,q)
q=a[q]
p=b+2
if(!(p<s))return A.b(a,p)
p=a[p]
if(!(r===73&&q===68&&p===51))return 0
r=b+3
if(!(r<s))return A.b(a,r)
if(a[r]!==255){r=b+4
if(!(r<s))return A.b(a,r)
r=a[r]===255}else r=!0
if(r)return 0
for(o=0,n=6;n<10;++n){r=b+n
if(!(r<s))return A.b(a,r)
r=a[r]
if((r&128)!==0)return 0
o=(o<<7|r)>>>0}r=b+5
if(!(r<s))return A.b(a,r)
m=(a[r]&16)!==0?10:0
return 10+o+m},
de(a,b){var s,r,q,p=A.cp(a,b)
if(p>0)return p
s=a.length
r=!1
if(b+128===s){if(!(b>=0&&b<s))return A.b(a,b)
if(a[b]===84){q=b+1
if(!(q<s))return A.b(a,q)
if(a[q]===65){r=b+2
if(!(r<s))return A.b(a,r)
r=a[r]===71
s=r}else s=r}else s=r}else s=r
if(s)return 128
return 0},
df(a,b){var s,r,q,p,o=a.length
if(!(b>=0&&b<o))return A.b(a,b)
s=a[b]
r=b+1
if(!(r<o))return A.b(a,r)
r=a[r]
q=b+2
if(!(q<o))return A.b(a,q)
q=a[q]
p=b+3
if(!(p<o))return A.b(a,p)
return(s<<24|r<<16|q<<8|a[p])>>>0},
hK(a,b,c){var s,r,q=c.length,p=a.length
if(b+q>p)return!1
for(s=0;s<q;++s){r=b+s
if(!(r>=0&&r<p))return A.b(a,r)
if(a[r]!==c.charCodeAt(s))return!1}return!0},
k_(a,b,c){var s,r,q,p,o,n,m
if(c.a===3)s=c.d===1?17:32
else s=c.d===1?9:17
r=c.f?2:0
q=b+4+s+r
for(p=0;p<2;++p){if(!A.hK(a,q,B.aD[p]))continue
o=q+8
r=a.length
if(o>r)return new A.bM()
n=A.df(a,q+4)
if((n&1)!==0&&o+4<=r){A.df(a,o)
o+=4}if((n&2)!==0&&o+4<=r)A.df(a,o)
return new A.bM()}m=b+36
if(A.hK(a,m,"VBRI")&&m+18<=a.length){A.df(a,m+14)
A.df(a,m+10)
return new A.bM()}return null},
iB(a1){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b=A.de(a1,0),a=a1.length,a0=0
for(;;){if(!(b>0&&a0+b<=a))break
a0+=b
b=A.de(a1,a0)}s=A.iz(a1,a0)
if(s<0){for(r=a0;r+4<=a;++r)if(A.jE(a1,r))throw A.a(B.ad)
throw A.a(B.aq)}q=A.eQ(a1,s)
q.toString
p=A.k_(a1,s,q)==null?s:s+q.b
o=t.t
n=A.i([],o)
m=A.i([],o)
l=A.i([],o)
for(o=q.a,k=q.c,j=p,i=0,h=0;j+4<=a;){g=A.de(a1,j)
if(g>0){j+=g
continue}f=A.eQ(a1,j)
if(f!=null&&f.a===o&&f.c===k){e=f.b
d=j+e
if(d>a)break
B.b.j(n,j)
B.b.j(m,e)
B.b.j(l,i)
i+=f.e
j=d
continue}c=A.iA(a1,j+1,q)
if(c<0)break;++h
j=c}if(n.length===0)throw A.a(B.ae)
return new A.dC(A.i([new A.a7(B.t,k,q.d,null)],t.J),a1,new Uint32Array(A.bo(n)),new Uint32Array(A.bo(m)),new Uint32Array(A.bo(l)),k,q.e)},
iz(a,b){var s,r,q
for(s=a.length,r=b;r+4<=s;++r){q=A.de(a,r)
if(q>0){r+=q-1
continue}if(A.h2(a,r,null))return r}return-1},
iA(a,b,c){var s,r=b+131072,q=a.length
if(r<q)q=r
for(s=b;s+4<=q;++s){if(A.de(a,s)>0)return s
if(A.h2(a,s,c))return s}return-1},
h2(a,b,c){var s,r,q,p=A.eQ(a,b)
if(p==null)return!1
if(c!=null)s=!(p.a===c.a&&p.c===c.c)
else s=!1
if(s)return!1
r=b+p.b
s=a.length
if(r>s)return!1
if(r+4>s)return!0
q=A.eQ(a,r)
return q!=null&&q.a===p.a&&q.c===p.c},
ew:function ew(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
bM:function bM(){},
dC:function dC(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.z=0
_.Q=!1},
iE(a){var s,r,q,p,o,n,m,l,k=A.ap(a,0,null),j=A.aT(k,0,k.byteLength),i=j.$ti
j=new A.E(j.a(),i.h("E<1>"))
i=i.c
for(;;){if(!j.n()){s=null
break}r=j.b
s=r==null?i.a(r):r
if(s.a==="moov")break}if(s==null)throw A.a(B.aj)
q=A.N(k,s,"mvhd")
p=1e6
if(q!=null&&q.b<q.c){j=q.b
i=k.getUint8(j)===1?16:8
o=j+4+i
if(o+4<=q.c){n=k.getUint32(o,!1)
p=n>0?n:1e6}}m=A.i([],t.J)
l=A.i([],t.fx)
for(j=A.aT(k,s.b,s.c),i=j.$ti,j=new A.E(j.a(),i.h("E<1>")),i=i.c;j.n();){r=j.b
if(r==null)r=i.a(r)
if(r.a!=="trak")continue
A.iC(k,a,r,m,l,p)}if(m.length===0)throw A.a(B.ac)
if(l.length===0)throw A.a(B.aa)
B.b.bu(l,new A.dF())
return new A.dD(m,a,l)},
iC(b3,b4,b5,b6,b7,b8){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1={},b2=b6.length
A.iD(b3,A.N(b3,b5,"tkhd"))
s=A.N(b3,b5,"mdia")
if(s==null)return
r=A.N(b3,s,"mdhd")
b1.a=1e6
if(r!=null){q=r.b
p=b3.getUint8(q)===1?16:8
o=b3.getUint32(q+4+p,!1)
b1.a=o
if(o<=0)b1.a=1e6}n=A.N(b3,s,"hdlr")
m=n!=null&&A.hE(b3,n.b+8)==="vide"
l=A.N(b3,s,"minf")
k=l==null?null:A.N(b3,l,"stbl")
if(k==null)return
j=A.N(b3,k,"stsd")
if(j==null)return
i=A.jW(b3,j,m)
if(i==null)return
h=A.jY(b3,A.N(b3,k,"stsz"))
q=h.length
g=A.jZ(b3,A.N(b3,k,"stts"),q)
f=A.jU(b3,A.N(b3,k,"ctts"),q)
e=A.k5(b3,k,h)
d=A.jX(b3,A.N(b3,k,"stss"),q)
c=new A.dE(b1)
b=A.jV(b3,A.N(b3,b5,"edts"),b8)
p=c.$1(b.b)
if(typeof p!=="number")return A.f0(p)
a=b.a-p
for(p=g.length,a0=d==null,a1=f.length,a2=e.length,a3=0,a4=0;a4<q;++a4){a5=c.$1(a3)
if(typeof a5!=="number")return a5.br()
if(!(a4<a1))return A.b(f,a4)
a6=c.$1(a3+f[a4])
if(typeof a6!=="number")return a6.br()
if(!(a4<a2))return A.b(e,a4)
a7=e[a4]
a8=h[a4]
if(!(a4<p))return A.b(g,a4)
a9=c.$1(a3+g[a4])
b0=c.$1(a3)
if(typeof a9!=="number")return a9.cr()
if(typeof b0!=="number")return A.f0(b0)
a9=a0?!0:d.c2(0,a4)
B.b.j(b7,new A.ak(b2,a7,a8,a5+a,a6+a,a9))
a3+=g[a4]}if(i.a){i.b.toString
q=new A.bh()}else{q=i.c
q.toString
q=new A.a7(q,i.f,i.r,i.w)}B.b.j(b6,q)},
iD(a,b){var s,r,q,p,o,n,m
if(b==null)return 0
s=b.b
r=a.getUint8(s)===1?32:20
q=s+4+r+16
if(q+36>b.c)return 0
p=a.getInt32(q,!1)
o=a.getInt32(q+4,!1)
n=a.getInt32(q+12,!1)
m=a.getInt32(q+16,!1)
if(p===65536&&o===0&&n===0&&m===65536)return 0
s=p===0
if(s&&o===65536&&n===-65536&&m===0)return 90
if(p===-65536&&o===0&&n===0&&m===-65536)return 180
if(s&&o===-65536&&n===65536&&m===0)return 270
return 0},
aT(a,b,c){return new A.bn(A.kf(a,b,c),t.g6)},
kf(a,b,c){return function(){var s=a,r=b,q=c
var p=0,o=2,n=[],m,l,k,j,i,h,g,f
return function $async$aT(d,e,a0){if(e===1){n.push(a0)
p=o}for(;;)switch(p){case 0:m=r
case 3:if(!(l=m+8,l<=q)){p=5
break}k=s.getUint32(m,!1)
j=A.hE(s,m+4)
if(k===1){if(m+16>q){p=1
break}i=s.getUint32(l,!1)
h=s.getUint32(m+12,!1)
k=(B.a.a4(i,32)|h)>>>0
g=16}else{if(k===0)k=q-m
g=8}if(k<g||m+k>q){p=1
break}f=m+k
p=6
return d.b=new A.cZ(j,m+g,f),1
case 6:case 4:m=f
p=3
break
case 5:case 1:return 0
case 2:return d.c=n.at(-1),3}}}},
N(a,b,c){var s,r,q
for(s=A.aT(a,b.b,b.c),r=s.$ti,s=new A.E(s.a(),r.h("E<1>")),r=r.c;s.n();){q=s.b
if(q==null)q=r.a(q)
if(q.a===c)return q}return null},
hE(a,b){var s,r=A.i([],t.t)
for(s=0;s<4;++s)r.push(a.getUint8(b+s))
return A.he(r)},
hj(a,b,c,d){return new A.d_(!1,null,a,0,0,b,c,d)},
jW(a2,a3,a4){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b=null,a=A.aT(a2,a3.b+8,a3.c),a0=a.$ti,a1=new A.E(a.a(),a0.h("E<1>"))
if(a1.n()){a=a1.b
s=a==null?a0.c.a(a):a}else s=b
if(s==null)return b
r=s.a
if(a4){a=s.b
q=a2.getUint16(a+24,!1)
p=a2.getUint16(a+26,!1)
a=A.aT(a2,a+78,s.c)
a0=a.$ti
a=new A.E(a.a(),a0.h("E<1>"))
a0=a0.c
for(;;){if(!a.n()){o=b
break}n=a.b
if(n==null)n=a0.a(n)
m=n.a
if(m==="avcC"||m==="hvcC"||m==="av1C"){a=n.b
n=n.c
o=A.fn(J.fd(B.i.gG(a2),a2.byteOffset),a,n)
break}}switch(r){case"avc1":case"avc3":l=B.aY
break
case"hev1":case"hvc1":l=B.aZ
break
case"av01":l=B.b_
break
default:return b}return new A.d_(!0,l,b,q,p,0,0,o==null?b:new A.aD(o))}a=s.b
k=a2.getUint16(a+16,!1)
j=a2.getUint32(a+24,!1)>>>16
i=a+28
if(r==="mp4a"){a=A.aT(a2,i,s.c)
a0=a.$ti
a=new A.E(a.a(),a0.h("E<1>"))
a0=a0.c
for(;;){if(!a.n()){h=b
break}n=a.b
if(n==null)n=a0.a(n)
if(n.a==="esds"){h=A.jl(a2,n)
break}}if(j!==0)a=j
else a=h==null?0:A.jm(h)
return A.hj(B.m,a,k,h==null?b:new A.aD(h))}if(r==="Opus"){a=A.aT(a2,i,s.c)
a0=a.$ti
a=new A.E(a.a(),a0.h("E<1>"))
a0=a0.c
for(;;){if(!a.n()){g=b
break}n=a.b
if(n==null)n=a0.a(n)
if(n.a==="dOps"){f=new Uint8Array(19)
B.d.X(f,0,8,new A.cx("OpusHead"))
f[8]=1
a=n.b
e=a2.getUint8(a+1)
f[9]=e===0?k:e
d=a2.getUint16(a+2,!1)
c=A.ap(f,0,b)
c.$flags&2&&A.K(c,10)
c.setUint16(10,d,!0)
c.setUint32(12,j===0?48e3:j,!0)
g=f
break}}a=j===0?48e3:j
return A.hj(B.n,a,k,g==null?b:new A.aD(g))}return b},
jm(a){var s,r,q,p={}
p.a=0
p=new A.eL(p,a)
s=p.$1(5)
if((s===31?p.$1(6):s)<0)return 0
r=p.$1(4)
if(r<0)return 0
if(r===15){q=p.$1(24)
return q<0?0:q}return r<13?B.aI[r]:0},
jl(a,b){var s,r,q,p,o,n,m=A.fB(a,b.b+4,b.c)
if(m==null||m.a!==3)return null
s=m.b+3
for(r=m.c;s<r;){q=A.fB(a,s,r)
if(q==null)break
if(q.a===4){p=q.b+13
for(o=q.c;p<o;){n=A.fB(a,p,o)
if(n==null)break
if(n.a===5){r=n.b
o=n.c
return A.fn(J.fd(B.i.gG(a),a.byteOffset),r,o)}p=n.d}}s=q.d}return null},
fB(a,b,c){var s,r,q,p,o,n,m=b+1
if(m>c)return null
s=a.getUint8(b)
for(r=0,q=0;q<4;++q,m=p){if(m>=c)return null
p=m+1
o=a.getUint8(m)
r=(r<<7|o&127)>>>0
if((o&128)===0){m=p
break}}n=m+r
if(n>c)return null
return new A.ea(s,m,n,n)},
jY(a,b){var s,r,q,p,o
if(b==null)return B.M
s=b.b+4
r=a.getUint32(s,!1)
q=a.getUint32(s+4,!1)
s+=8
if(r!==0)return A.aH(q,r,!1,t.S)
p=A.aH(q,0,!1,t.S)
for(o=0;o<q;++o)B.b.t(p,o,a.getUint32(s+o*4,!1))
return p},
jZ(a,b,c){var s,r,q,p,o,n,m,l,k=A.aH(c,0,!1,t.S)
if(b==null)return k
s=b.b+4
r=a.getUint32(s,!1)
s+=4
q=0
p=0
for(;;){if(!(p<r&&q<c))break
o=a.getUint32(s,!1)
n=a.getUint32(s+4,!1)
s+=8
m=0
for(;;){if(!(m<o&&q<c))break
l=q+1
B.b.t(k,q,n);++m
q=l}++p}return k},
jU(a,b,c){var s,r,q,p,o,n,m,l,k,j,i,h=A.aH(c,0,!1,t.S)
if(b==null)return h
s=b.b
r=a.getUint8(s)
q=s+4
p=a.getUint32(q,!1)
q+=4
s=r===1
o=0
n=0
for(;;){if(!(n<p&&o<c))break
m=a.getUint32(q,!1)
l=q+4
k=s?a.getInt32(l,!1):a.getUint32(l,!1)
q+=8
j=0
for(;;){if(!(j<m&&o<c))break
i=o+1
B.b.t(h,o,k);++j
o=i}++n}return h},
jV(a,b,c){var s,r,q,p,o,n,m,l,k,j,i,h,g,f
if(b==null||c<=0)return B.Q
s=A.N(a,b,"elst")
if(s==null||s.b+8>s.c)return B.Q
r=s.b
q=a.getUint8(r)===1
p=q?20:12
o=r+4
n=a.getUint32(o,!1)
o+=4
for(r=s.c,m=0,l=0,k=!1,j=0;j<n;++j,o=i){i=o+p
if(i>r)break
h=o+4
if(q){g=(B.a.a4(a.getUint32(o,!1),32)|a.getUint32(h,!1))>>>0
h=o+8
f=a.getInt32(h,!1)*4294967296+a.getUint32(h+4,!1)}else{g=a.getUint32(o,!1)
f=a.getInt32(h,!1)}if(f<0){if(!k)m+=g
continue}if(!k){l=f
k=!0}}return new A.d1(B.a.u(m*1e6,c),l)},
jX(a,b,c){var s,r,q,p
if(b==null)return null
s=b.b+4
r=a.getUint32(s,!1)
s+=4
q=A.iy(t.S)
for(p=0;p<r;++p){q.j(0,a.getUint32(s,!1)-1)
s+=4}return q},
k5(a0,a1,a2){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d=A.jT(a0,a1),c=A.N(a0,a1,"stsc"),b=a2.length,a=A.aH(b,0,!1,t.S)
if(d.length===0||c==null)return a
s=c.b+4
r=a0.getUint32(s,!1)
s+=4
q=t.t
p=A.i([],q)
o=A.i([],q)
for(n=0;n<r;++n){B.b.j(p,a0.getUint32(s,!1))
B.b.j(o,a0.getUint32(s+4,!1))
s+=12}m=0
n=0
l=1
k=0
for(;;){q=d.length
if(!(k<q&&m<b))break
j=o.length
i=p.length
h=k+1
for(;;){if(n<i){if(!(n>=0))return A.b(p,n)
g=p[n]<=h}else g=!1
if(!g)break
if(!(n>=0&&n<j))return A.b(o,n)
l=o[n];++n}if(!(k<q))return A.b(d,k)
f=d[k]
e=0
for(;;){if(!(e<l&&m<b))break
B.b.t(a,m,f)
if(!(m>=0&&m<b))return A.b(a2,m)
f+=a2[m];++m;++e}k=h}return a},
jT(a,b){var s,r,q,p,o,n,m=A.N(a,b,"stco")
if(m!=null){s=m.b+4
r=a.getUint32(s,!1)
s+=4
q=A.i([],t.t)
for(p=0;p<r;++p)q.push(a.getUint32(s+p*4,!1))
return q}o=A.N(a,b,"co64")
if(o!=null){s=o.b+4
r=a.getUint32(s,!1)
s+=4
q=A.i([],t.t)
for(p=0;p<r;++p){n=s+p*8
q.push((B.a.a4(a.getUint32(n,!1),32)|a.getUint32(n+4,!1))>>>0)}return q}return B.M},
cZ:function cZ(a,b,c){this.a=a
this.b=b
this.c=c},
ak:function ak(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.r=f},
dD:function dD(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.d=0
_.e=!1},
dF:function dF(){},
dE:function dE(a){this.a=a},
dG:function dG(){},
d_:function d_(a,b,c,d,e,f,g,h){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.w=h},
eL:function eL(a,b){this.a=a
this.b=b},
ea:function ea(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
d1:function d1(a,b){this.a=a
this.b=b},
hQ(a,b){var s
if(a.length<8)return!1
for(s=0;s<8;++s)if(a[s]!==b[s])return!1
return!0},
iK(b1){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0=A.ap(b1,0,null)
if(b0.byteLength<27||!A.hL(b0,0))throw A.a(B.a9)
s=A.i([],t.eS)
r=new A.e9($.fc())
for(q=-1,p=0;o=p+27,o<=b0.byteLength;p=l){if(!A.hL(b0,p))throw A.a(B.an)
n=b0.getUint8(p+26)
m=o+n
if(m>b0.byteLength)throw A.a(B.ai)
for(l=m,k=0;k<n;++k,l=i){j=b0.getUint8(o+k)
i=l+j
if(i>b0.byteLength)throw A.a(B.ap)
r.j(0,J.dj(B.i.gG(b0),b0.byteOffset+l,j))
if(j<255){B.b.j(s,r.ck())
r.J(0)}}h=b0.getUint32(p+6,!0)
g=b0.getUint32(p+10,!0)
if(!(h===4294967295&&g===4294967295))q=(B.a.a4(g,32)|h)>>>0}if(s.length===0||!A.hQ(B.b.gbg(s),B.K))throw A.a(B.a7)
f=B.b.gbg(s)
if(f.length>=19){e=f[9]
d=(f[12]|f[13]<<8|f[14]<<16|f[15]<<24)>>>0
if(d<=0)d=48e3}else{d=48e3
e=2}c=B.b.bv(s,s.length>1&&A.hQ(s[1],B.aH)?2:1)
b=A.kI(f)
o=c.length
a=t.S
a0=A.aH(o,0,!1,a)
a1=c.length
a2=A.aH(a1,0,!1,a)
for(a3=0,k=0;k<c.length;++k){a4=A.kJ(c[k])
B.b.t(a2,k,a4>0?a4:960)
a5=a3-b
B.b.t(a0,k,a5>0?a5:0)
if(!(k<a1))return A.b(a2,k)
a3+=a2[k]}a6=(q>b?q:a3)-b
for(a=a6>0,k=0;a7=c.length,k<a7;k=a8){a8=k+1
if(a8<a7){if(!(a8<o))return A.b(a0,a8)
a9=a0[a8]}else a9=a?a6:0
if(!(k<o))return A.b(a0,k)
a4=a9-a0[k]
if(a4<0)a7=0
else{if(!(k<a1))return A.b(a2,k)
a7=a2[k]
a7=a4>a7?a7:a4}B.b.t(a2,k,a7)}o=A.i([new A.a7(B.n,d,e,new A.aD(f))],t.J)
return new A.dJ(o,c,a0,a2)},
hL(a,b){var s
if(b+4>a.byteLength)return!1
for(s=0;s<4;++s)if(a.getUint8(b+s)!==B.aA[s])return!1
return!0},
dJ:function dJ(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.f=0
_.r=!1},
co(a){var s
switch(a.a){case 0:s=1
break
case 1:s=2
break
case 2:s=3
break
case 3:s=4
break
default:s=null}return s},
iR(a){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c="wav",b=A.ap(a,0,null)
if(b.byteLength<12||!A.hD(b,0,"RIFF")||!A.hD(b,8,"WAVE"))throw A.a(B.ao)
for(s=-1,r=0,q=-1,p=0,o=12;n=o+8,n<=b.byteLength;o=j){m=A.k0(b,o)
l=b.getUint32(o+4,!0)
if(m==="fmt "){r=l
s=n}else if(m==="data"){k=b.byteLength
p=n+l>k?k-n:l
if(l===0){p=k-n
q=n
break}q=n}j=(n+l+1&4294967294)>>>0
if(j<=o)break}if(s<0||r<16)throw A.a(B.al)
if(q<0)throw A.a(B.ag)
i=b.getUint16(s,!0)
h=b.getUint16(s+2,!0)
g=b.getUint32(s+4,!0)
f=b.getUint16(s+14,!0)
if(i===65534){if(r<40||s+40>b.byteLength)throw A.a(B.af)
e=b.getUint16(s+18,!0)
k=s+24
if(!A.jL(b,k))throw A.a(B.a8)
i=b.getUint16(k,!0)}else e=f
k=i===1
if(!k&&i!==3)throw A.a(A.dn(c,"unsupported WAVE format tag "+i))
if(e===0)e=f
if(e!==f)throw A.a(A.dn(c,"valid bits "+e+" != container "+f))
if(k&&f===8)d=B.R
else if(k&&f===16)d=B.S
else if(k&&f===24)d=B.T
else{if(!(i===3&&f===32))throw A.a(A.dn(c,"unsupported PCM: fmt="+i+" bits="+f))
d=B.U}A:{if(B.R===d||B.S===d){k=B.X
break A}if(B.T===d||B.U===d){k=B.Y
break A}k=null}if(h<1||h>8||g<1)throw A.a(A.dn(c,"bad ch="+h+" sr="+g))
return new A.dY(b,q,p,g,h,d,A.i([new A.a7(k,g,h,null)],t.J))},
jL(a,b){var s,r
if(b+16>a.byteLength)return!1
for(s=b+2,r=0;r<14;++r)if(a.getUint8(s+r)!==B.aE[r])return!1
return!0},
hD(a,b,c){var s,r,q
if(b+4>a.byteLength)return!1
for(s=c.length,r=0;r<4;++r){q=a.getUint8(b+r)
if(!(r<s))return A.b(c,r)
if(q!==c.charCodeAt(r))return!1}return!0},
k0(a,b){var s,r=A.i([],t.t)
for(s=0;s<4;++s)r.push(a.getUint8(b+s))
return A.he(r)},
bm:function bm(a,b){this.a=a
this.b=b},
dY:function dY(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.w=0
_.x=!1},
kk(a,b){var s,r="codecString"
if(b.bf(r)){s=b.m(0,r)
s.toString
return s}A:{if(B.m===a){s="mp4a.40.2"
break A}if(B.n===a){s="opus"
break A}if(B.t===a){s="mp3"
break A}if(B.W===a){s="flac"
break A}if(B.V===a){s="vorbis"
break A}s=A.D(A.bY("WebCodecs audio: no codec string for "+a.i(0)))}return s},
fo(a){var s=0,r=A.z(t.g0),q,p,o,n,m,l,k
var $async$fo=A.A(function(b,c){if(b===1)return A.w(c,r)
for(;;)switch(s){case 0:n=a.c
m=a.d
l=new A.cV(A.i([],t.A))
k=A.kk(a.a,a.e)
l.a=A.a_(new v.G.AudioDecoder({output:A.fy(new A.e_(l)),error:A.fy(new A.e0(l))}))
p=a.b
o=p!=null&&p.length!==0?{codec:k,sampleRate:n,numberOfChannels:m,description:new Uint8Array(A.bo(p))}:{codec:k,sampleRate:n,numberOfChannels:m}
l.a.configure(o)
l.a5()
q=l
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$fo,r)},
cV:function cV(a){var _=this
_.a=null
_.b=a
_.d=_.c=null},
dZ:function dZ(){},
e_:function e_(a){this.a=a},
e0:function e0(a){this.a=a},
R(a){return A.kl(a)},
kl(a8){var s=0,r=A.z(t.H),q,p=2,o=[],n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7
var $async$R=A.A(function(a9,b0){if(a9===1){o.push(b0)
s=p}for(;;)switch(s){case 0:a3={}
a4=a8.r
a4.toString
n=t.eE.a(a4)
a4=J.fQ(n,"ring")
a4.toString
a4=t.u.a(a4).a
a4.toString
a4=A.kn(a4)
b=J.eZ(a4)
if(b.gaa(a4)<=64)A.D(A.aC(b.gaa(a4),"buffer","too small to hold a ring"))
m=new A.dL(b.ba(a4,0,16),b.b9(a4,64,B.a.D(b.gaa(a4)-64,4)))
a3.a=a3.b=!1
a3.c=0
a3.d=null
a3.e=0
a3.f=a3.r=null
l=null
k=null
a8.c9(new A.eV(a3,m))
p=4
a4=J.fQ(n,"bytes")
a4.toString
l=A.im(t.p.a(a4),null)
if(l==null)throw A.a(B.am)
j=A.jn(l.gO())
i=t.V.a(B.b.m(l.gO(),j))
a4=i
b=a4.a
a=a4.d
a=a==null?null:a.c
s=7
return A.J(A.fo(new A.dl(b,a,a4.b,a4.c,B.aJ)),$async$R)
case 7:k=b0
h=new A.eW(a3)
a4=t.H,b=v.G
case 8:if(!!a3.b){s=9
break}g=a3.d
s=g!=null?10:11
break
case 10:a3.d=null
s=12
return A.J(l.v(g),$async$R)
case 12:s=13
return A.J(k.U(),$async$R)
case 13:a=m.b
a0=A.u(b.Atomics.load(a,1))
A.u(b.Atomics.store(a,0,a0))
a3.r=null
a3.a=!1;++a3.e
s=8
break
case 11:s=14
return A.J(l.B(),$async$R)
case 14:f=b0
s=f==null?15:16
break
case 15:a3.a=!0
a7=J
s=17
return A.J(k.U(),$async$R)
case 17:a=a7.cr(b0)
case 18:if(!a.n()){s=19
break}e=a.gA()
a0=a3.c
s=20
return A.J(A.db(m,e,h),$async$R)
case 20:a1=b0
if(typeof a1!=="number"){q=A.f0(a1)
s=1
break}a3.c=a0+a1
s=18
break
case 19:case 21:if(!(!a3.b&&a3.d==null)){s=22
break}s=23
return A.J(A.fY(B.G,a4),$async$R)
case 23:s=21
break
case 22:s=8
break
case 16:if(f.f!==j){s=8
break}a7=J
s=24
return A.J(k.a9(f),$async$R)
case 24:a=a7.cr(b0)
case 25:if(!a.n()){s=26
break}d=a.gA()
if(a3.r==null)a3.r=d.e
a0=a3.c
s=27
return A.J(A.db(m,d,h),$async$R)
case 27:a1=b0
if(typeof a1!=="number"){q=A.f0(a1)
s=1
break}a3.c=a0+a1
if(h.$0()){s=26
break}s=25
break
case 26:s=8
break
case 9:p=2
s=6
break
case 4:p=3
a5=o.pop()
c=A.P(a5)
a3.f=c
s=6
break
case 3:s=2
break
case 6:s=28
return A.J(a8.c.a,$async$R)
case 28:p=30
a4=k
a4=a4==null?null:a4.q()
b=t.H
s=33
return A.J(a4 instanceof A.f?a4:A.ed(a4,b),$async$R)
case 33:a4=l
a4=a4==null?null:a4.q()
s=34
return A.J(a4 instanceof A.f?a4:A.ed(a4,b),$async$R)
case 34:p=2
s=32
break
case 30:p=29
a6=o.pop()
s=32
break
case 29:s=2
break
case 32:case 1:return A.x(q,r)
case 2:return A.w(o.at(-1),r)}})
return A.y($async$R,r)},
db(a,b,c){var s=0,r=A.z(t.S),q,p,o,n,m,l
var $async$db=A.A(function(d,e){if(d===1)return A.w(e,r)
for(;;)switch(s){case 0:o=b.a
n=b.b
m=t.H
l=0
case 3:if(!(l<n&&!c.$0())){s=4
break}p=a.cm(o,n-l,l)
l+=p
s=p===0?5:6
break
case 5:s=7
return A.J(A.fY(B.G,m),$async$db)
case 7:case 6:s=3
break
case 4:q=l
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$db,r)},
jn(a){var s,r
for(s=a.length,r=0;r<s;++r)if(a[r] instanceof A.a7)return r
throw A.a(B.ak)},
kG(){A.kM(A.km())
return null},
eV:function eV(a,b){this.a=a
this.b=b},
eW:function eW(a){this.a=a},
dL:function dL(a,b){this.b=a
this.c=b},
bZ:function bZ(a,b){this.a=a
this.b=b},
ab:function ab(a,b){this.a=a
this.b=b},
as:function as(a,b){this.a=a
this.b=b},
ae:function ae(){},
bh:function bh(){},
a7:function a7(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
dl:function dl(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
dn(a,b){return new A.v(a,b)},
dB:function dB(){},
v:function v(a,b){this.b=a
this.a=b},
ar:function ar(a,b){this.b=a
this.a=b},
at:function at(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.e=d
_.f=e},
aD:function aD(a){this.c=a},
b0:function b0(a,b,c){this.a=a
this.b=b
this.e=c},
kM(a){var s={}
s.a=null
A.a_(v.G.self).onmessage=A.fy(new A.fa(s,a))},
js(a){var s,r,q,p,o,n,m,l,k,j,i,h=null
if(a!=null){q=A.iv(a,"Object")
q=!q}else q=!0
if(q)return h
A.a_(a)
s=t.dE.a(a.h)
if(s==null)return h
r=null
try{q=s
p=q.byteLength
if(p<12)A.D(A.fe("spawn envelope: need at least 12 bytes, got "+p))
o=A.ap(q,0,12)
n=o.getUint8(0)
if(n!==1)A.D(A.fe("spawn envelope: unsupported version "+n+" (expected 1)"))
m=o.getUint8(1)
l=A.iS(m)
if(l==null)A.D(A.fe("spawn envelope: unknown kind "+m))
r=new A.cW(n,l,o.getUint16(2,!0),o.getUint32(4,!0),o.getUint32(8,!0))}catch(k){if(A.P(k) instanceof A.cC)return h
else throw k}j=a.p
if(j==null)i=h
else i=r.c!==0||r.b===B.q||r.b===B.r||r.b===B.j?t.Y.a(j):A.fx(j)
return new A.U(r.b,r.c,r.d,i)},
kc(a,b){var s,r,q=t.c.a(new v.G.Array()),p=new A.eT(A.i([],t.f),q)
for(s=b.length,r=0;r<b.length;b.length===s||(0,A.cq)(b),++r)p.$1(b[r])
return q},
fE(a,b){var s,r,q,p,o
if(a==null)return null
if(a instanceof A.bd){s={}
r=a.a
s.$spawn$platform=r
if(r!=null&&A.hB(r)!=="SharedArrayBuffer")B.b.j(b,r)
return s}if(A.dc(a))return a
if(A.cl(a))return a
if(typeof a=="number")return a
if(typeof a=="string")return a
if(t.x.b(a))return t.q.a(a)
if(t.p.b(a))return a
if(t.U.b(a))return a
if(t.go.b(a))return a
if(t.dQ.b(a))return a
if(t.h7.b(a))return a
if(t.an.b(a))return a
if(t.bv.b(a))return a
if(t.w.b(a))return a
if(t.gN.b(a))return a
if(t.e.b(a))return a
if(t.j.b(a)){q=t.c.a(new v.G.Array())
for(p=0;o=J.bv(a),p<o.gk(a);++p)q[p]=A.fE(o.m(a,p),b)
return q}if(t.G.b(a)){s={}
a.N(0,new A.eS(s,b))
return s}throw A.a(A.aC(a,"message","spawn cannot carry this value"))},
fx(a){var s,r,q,p
if(a==null)return null
if(typeof a==="boolean")return A.hz(a)
if(typeof a==="string")return A.al(a)
if(typeof a==="number"){A.da(a)
if(isFinite(a))s=a===(a<0?Math.ceil(a):Math.floor(a))
else s=!1
if(s)return B.l.bn(a)
return a}if(!(typeof a==="object"))return null
switch(A.hB(a)){case"ArrayBuffer":return t.q.a(a)
case"Uint8Array":return t.Y.a(a)
case"Int8Array":return t.cv.a(a)
case"Uint8ClampedArray":return t.gi.a(a)
case"Int16Array":return t.at.a(a)
case"Uint16Array":return t.dT.a(a)
case"Int32Array":return t.ha.a(a)
case"Uint32Array":return t.dk.a(a)
case"Float32Array":return t.E.a(a)
case"Float64Array":return t.c2.a(a)
case"DataView":return t.gT.a(a)
case"Array":t.c.a(a)
r=A.u(A.da(a.length))
s=[]
for(q=0;q<r;++q)s.push(A.fx(a[q]))
return s
default:A.a_(a)
if("$spawn$platform" in a)return new A.bd(a.$spawn$platform)
p=t.c.a(v.G.Object.keys(a))
r=A.u(A.da(p.length))
s=A.h0(t.N,t.X)
for(q=0;q<r;++q)s.t(0,A.al(p[q]),A.fx(a[A.al(p[q])]))
return s}},
hB(a){var s,r=A.ft(A.a_(a).constructor)
if(r==null)s=null
else{s=A.fv(r.name)
if(s==null)s=null}return s},
fa:function fa(a,b){this.a=a
this.b=b},
f9:function f9(){},
d9:function d9(a,b){this.a=a
this.b=b},
eT:function eT(a,b){this.a=a
this.b=b},
eS:function eS(a,b){this.a=a
this.b=b},
dN:function dN(a,b){this.a=a
this.b=b},
dO:function dO(a,b){this.a=a
this.b=b},
dM:function dM(){},
dg(a,b,c,d){return A.kL(a,b,c,d)},
kL(a,b,c,a0){var s=0,r=A.z(t.H),q=1,p=[],o=[],n,m,l,k,j,i,h,g,f,e,d
var $async$dg=A.A(function(a1,a2){if(a1===1){p.push(a2)
s=q}for(;;)switch(s){case 0:f=t.X
e=new A.cj(a,A.hc(f),new A.ai(new A.f($.h,t.D),t.h),A.i([],t.b4),c)
a.L(new A.U(B.q,0,0,B.k.a8(B.a4.c6(A.fi(["v",1,"caps",a0.bo()],t.N,f),null))))
f=a.a
n=new A.bj(f,A.B(f).h("bj<1>")).cb(e.gbN(),e.gbP())
q=3
f=b.$1(e)
s=6
return A.J(f instanceof A.f?f:A.ed(f,t.H),$async$dg)
case 6:o.push(5)
s=4
break
case 3:q=2
d=p.pop()
m=A.P(d)
l=A.S(d)
f=A.a0(m)
j=t.l.a(l)
i=e.a
h=J.ao(f)
g=A.O(h.gl(f).a,null)
f=h.i(f)
j=j.i(0)
i.L(new A.U(B.j,0,0,B.k.a8(g+"\n"+A.fN(f,"\n"," ")+"\n"+j)))
o.push(5)
s=4
break
case 2:o=[1]
case 4:q=1
e.am()
f=n
if(((f.e&=4294967279)&8)===0)f.aO()
f=f.f
s=7
return A.J(f==null?$.fb():f,$async$dg)
case 7:a.L(B.au)
s=o.pop()
break
case 5:return A.x(null,r)
case 1:return A.w(p.at(-1),r)}})
return A.y($async$dg,r)},
cj:function cj(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=null
_.f=!1
_.r=e},
eI:function eI(a,b){this.a=a
this.b=b},
eJ:function eJ(a,b){this.a=a
this.b=b},
eK:function eK(a,b){this.a=a
this.b=b},
U:function U(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
kt(a){A.fw(a,A.i([],t.f),"message")
return new A.c8(0,a)},
fI(a,b){if(a===0)return b
if(!t.p.b(b))throw A.a(A.a9("spawn: frame declares typeId "+a+" but carries "+J.bx(b).i(0)+" instead of bytes"))
return $.ia().c3(a,b)},
fw(a,b,c){var s,r,q,p
if(a==null||A.dc(a)||typeof a=="number"||typeof a=="string"||t.ak.b(a)||t.x.b(a)||a instanceof A.bd)return
s=t.j.b(a)
if(s||t.G.b(a)){for(r=b.length,q=0;q<r;++q)if(b[q]===a)throw A.a(A.aC(a,c,"spawn cannot carry a cyclic structure"))
B.b.j(b,a)
if(s)for(s=c+"[",p=0;r=J.bv(a),p<r.gk(a);++p)A.fw(r.m(a,p),b,s+p+"]")
else if(t.G.b(a))a.N(0,new A.eO(c,b))
if(0>=b.length)return A.b(b,-1)
b.pop()
return}throw A.a(A.aC(a,c,"spawn cannot carry "+J.bx(a).i(0)+". Wrap a platform object (VideoFrame, AudioData, ImageBitmap, ...) in a PlatformValue. Portable values are null, bool, int, double, String, TypedData, ByteBuffer, and List/Map<String, ...> of those. Implement WireMessage for anything else."))},
eO:function eO(a,b){this.a=a
this.b=b},
bd:function bd(a){this.a=a},
iS(a){var s,r
for(s=0;s<6;++s){r=B.az[s]
if(r.c===a)return r}return null},
ah:function ah(a,b,c){this.c=a
this.a=b
this.b=c},
cW:function cW(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
e1:function e1(a){this.a=a},
ap(a,b,c){var s=a.BYTES_PER_ELEMENT
c=A.cO(b,c,B.a.u(a.byteLength,s))
return J.id(B.d.gG(a),a.byteOffset+b*s,(c-b)*s)},
fn(a,b,c){var s=a.BYTES_PER_ELEMENT
c=A.cO(b,c,B.a.u(a.byteLength,s))
return J.dj(B.d.gG(a),a.byteOffset+b*s,(c-b)*s)},
im(a,b){var s,r,q,p,o,n,m=A.io(a)
switch(m){case B.F:return A.iR(a)
case B.E:return A.iK(a)
case B.D:s=A.ap(a,0,null)
r=A.fS(a)
q=A.eP(s,r)
if(q==null)A.D(B.ah)
m=q.b
if(!(m<16))return A.b(B.L,m)
p=B.L[m]
if(p!==0){o=q.c
o=(o===7?8:o)<1}else o=!0
if(o)A.D(B.ab)
o=q.c
n=new Uint8Array(2)
n[0]=m>>>1&7|16
n[1]=(m&1)<<7|(o&15)<<3
m=o===7?8:o
return new A.dk(A.i([new A.a7(B.m,p,m,new A.aD(n))],t.J),a,s,p,r,q.a)
case B.o:return A.iB(a)
case B.C:case B.ar:return A.iE(a)
default:return null}},
io(a){var s,r,q,p,o,n=a.length
if(n>=12&&a[0]===82&&a[1]===73&&a[2]===70&&a[3]===70&&a[8]===87&&a[9]===65&&a[10]===86&&a[11]===69)return B.F
if(n>=4&&a[0]===79&&a[1]===103&&a[2]===103&&a[3]===83)return B.E
if(n>=8&&a[4]===102&&a[5]===116&&a[6]===121&&a[7]===112)return B.C
s=A.cp(a,0)
r=0
for(;;){if(!(s>0&&r+s<=n))break
r+=s
s=A.cp(a,r)}q=r>0
if(q)for(;;){if(!(r<n&&a[r]===0))break;++r}if(r+2<=n){if(!(r>=0&&r<n))return A.b(a,r)
p=a[r]
o=r+1
if(!(o<n))return A.b(a,o)
o=a[o]
if(p===255&&(o&246)===240)return B.D
if(A.fK(p,o))return B.o}if(q)return B.o
return null},
kI(a){var s
if(a.length<12)return 0
for(s=0;s<8;++s)if(a[s]!==B.K[s])return 0
return(a[10]|a[11]<<8)>>>0},
kJ(a){var s,r,q,p,o=a.length
if(o===0)return 0
if(0>=o)return A.b(a,0)
s=a[0]
r=B.aC[s>>>3&31]
switch(s&3){case 0:q=1
break
case 1:case 2:q=2
break
default:if(o<2)return 0
q=a[1]&63}if(q<1||q>48)return 0
p=r*q
return p>5760?0:p},
kn(a){var s
if(t.x.b(a))return a
s=t.g.a(v.G.Uint8Array)
A.a_(a)
return B.d.gG(t.Y.a(A.ko(s,[a],t.m)))}},B={}
var w=[A,J,B]
var $={}
A.fg.prototype={}
J.cE.prototype={
H(a,b){return a===b},
gp(a){return A.bQ(a)},
i(a){return"Instance of '"+A.cN(a)+"'"},
gl(a){return A.a6(A.fz(this))}}
J.cG.prototype={
i(a){return String(a)},
gp(a){return a?519018:218159},
gl(a){return A.a6(t.y)},
$il:1,
$ian:1}
J.bG.prototype={
H(a,b){return null==b},
i(a){return"null"},
gp(a){return 0},
gl(a){return A.a6(t.P)},
$il:1,
$ir:1}
J.bI.prototype={$iq:1}
J.av.prototype={
gp(a){return 0},
gl(a){return B.aS},
i(a){return String(a)}}
J.cM.prototype={}
J.bW.prototype={}
J.ac.prototype={
i(a){var s=a[$.fO()]
if(s==null)return this.bw(a)
return"JavaScript function for "+J.aY(s)},
$iaE:1}
J.b3.prototype={
gp(a){return 0},
i(a){return String(a)}}
J.b4.prototype={
gp(a){return 0},
i(a){return String(a)}}
J.p.prototype={
j(a,b){A.aa(a).c.a(b)
a.$flags&1&&A.K(a,29)
a.push(b)},
c_(a,b){A.aa(a).h("e<1>").a(b)
a.$flags&1&&A.K(a,"addAll",2)
this.bA(a,b)
return},
bA(a,b){var s,r
t.b.a(b)
s=b.length
if(s===0)return
if(a===b)throw A.a(A.b_(a))
for(r=0;r<s;++r)a.push(b[r])},
J(a){a.$flags&1&&A.K(a,"clear","clear")
a.length=0},
bv(a,b){var s=a.length
if(b>s)throw A.a(A.ad(b,0,s,"start",null))
if(b===s)return A.i([],A.aa(a))
return A.i(a.slice(b,s),A.aa(a))},
gbg(a){if(a.length>0)return a[0]
throw A.a(A.it())},
c0(a,b){var s,r
A.aa(a).h("an(1)").a(b)
s=a.length
for(r=0;r<s;++r){if(b.$1(a[r]))return!0
if(a.length!==s)throw A.a(A.b_(a))}return!1},
bu(a,b){var s,r,q,p,o,n=A.aa(a)
n.h("c(1,1)?").a(b)
a.$flags&2&&A.K(a,"sort")
s=a.length
if(s<2)return
if(s===2){r=a[0]
q=a[1]
n=b.$2(r,q)
if(typeof n!=="number")return n.cq()
if(n>0){a[0]=q
a[1]=r}return}p=0
if(n.c.b(null))for(o=0;o<a.length;++o)if(a[o]===void 0){a[o]=null;++p}a.sort(A.bt(b,2))
if(p>0)this.bT(a,p)},
bT(a,b){var s,r=a.length
for(;s=r-1,r>0;r=s)if(a[s]===null){a[s]=void 0;--b
if(b===0)break}},
gbj(a){return a.length!==0},
i(a){return A.ff(a,"[","]")},
gK(a){return new J.bz(a,a.length,A.aa(a).h("bz<1>"))},
gp(a){return A.bQ(a)},
gk(a){return a.length},
m(a,b){if(!(b>=0&&b<a.length))throw A.a(A.eX(a,b))
return a[b]},
t(a,b,c){A.aa(a).c.a(c)
a.$flags&2&&A.K(a)
if(!(b>=0&&b<a.length))throw A.a(A.eX(a,b))
a[b]=c},
gl(a){return A.a6(A.aa(a))},
$ie:1,
$ij:1}
J.cF.prototype={
cl(a){var s,r,q
if(!Array.isArray(a))return null
s=a.$flags|0
if((s&4)!==0)r="const, "
else if((s&2)!==0)r="unmodifiable, "
else r=(s&1)!==0?"fixed, ":""
q="Instance of '"+A.cN(a)+"'"
if(r==="")return q
return q+" ("+r+"length: "+a.length+")"}}
J.dw.prototype={}
J.bz.prototype={
gA(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s,r=this,q=r.a,p=q.length
if(r.b!==p){q=A.cq(q)
throw A.a(q)}s=r.c
if(s>=p){r.d=null
return!1}r.d=q[s]
r.c=s+1
return!0},
$iau:1}
J.bH.prototype={
aw(a,b){var s
A.fu(b)
if(a<b)return-1
else if(a>b)return 1
else if(a===b){if(a===0){s=this.gaC(b)
if(this.gaC(a)===s)return 0
if(this.gaC(a))return-1
return 1}return 0}else if(isNaN(a)){if(isNaN(b))return 0
return 1}else return-1},
gaC(a){return a===0?1/a<0:a<0},
bn(a){var s
if(a>=-2147483648&&a<=2147483647)return a|0
if(isFinite(a)){s=a<0?Math.ceil(a):Math.floor(a)
return s+0}throw A.a(A.bY(""+a+".toInt()"))},
c1(a,b,c){if(B.a.aw(b,c)>0)throw A.a(A.aU(b))
if(this.aw(a,b)<0)return b
if(this.aw(a,c)>0)return c
return a},
i(a){if(a===0&&1/a<0)return"-0.0"
else return""+a},
gp(a){var s,r,q,p,o=a|0
if(a===o)return o&536870911
s=Math.abs(a)
r=Math.log(s)/0.6931471805599453|0
q=Math.pow(2,r)
p=s<1?s/q:q/s
return((p*9007199254740992|0)+(p*3542243181176521|0))*599197+r*1259&536870911},
ac(a,b){var s=a%b
if(s===0)return 0
if(s>0)return s
if(b<0)return s-b
else return s+b},
u(a,b){if((a|0)===a)if(b>=1||b<-1)return a/b|0
return this.b5(a,b)},
D(a,b){return(a|0)===a?a/b|0:this.b5(a,b)},
b5(a,b){var s=a/b
if(s>=-2147483648&&s<=2147483647)return s|0
if(s>0){if(s!==1/0)return Math.floor(s)}else if(s>-1/0)return Math.ceil(s)
throw A.a(A.bY("Result of truncating division is "+A.o(s)+": "+A.o(a)+" ~/ "+b))},
bt(a,b){if(b<0)throw A.a(A.aU(b))
return b>31?0:a<<b>>>0},
a4(a,b){return b>31?0:a<<b>>>0},
F(a,b){var s
if(a>0)s=this.b3(a,b)
else{s=b>31?31:b
s=a>>s>>>0}return s},
bX(a,b){if(0>b)throw A.a(A.aU(b))
return this.b3(a,b)},
b3(a,b){return b>31?0:a>>>b},
gl(a){return A.a6(t.o)},
$im:1,
$iaX:1}
J.bF.prototype={
aG(a,b){var s=this.bt(1,b-1)
return((a&s-1)>>>0)-((a&s)>>>0)},
gl(a){return A.a6(t.S)},
$il:1,
$ic:1}
J.cH.prototype={
gl(a){return A.a6(t.i)},
$il:1}
J.b2.prototype={
Z(a,b,c){return a.substring(b,A.cO(b,c,a.length))},
bs(a,b){var s,r
if(0>=b)return""
if(b===1||a.length===0)return a
if(b!==b>>>0)throw A.a(B.a5)
for(s=a,r="";;){if((b&1)===1)r=s+r
b=b>>>1
if(b===0)break
s+=s}return r},
cd(a,b,c){var s=b-a.length
if(s<=0)return a
return this.bs(c,s)+a},
i(a){return a},
gp(a){var s,r,q
for(s=a.length,r=0,q=0;q<s;++q){r=r+a.charCodeAt(q)&536870911
r=r+((r&524287)<<10)&536870911
r^=r>>6}r=r+((r&67108863)<<3)&536870911
r^=r>>11
return r+((r&16383)<<15)&536870911},
gl(a){return A.a6(t.N)},
gk(a){return a.length},
$il:1,
$ih4:1,
$iM:1}
A.e9.prototype={
j(a,b){var s,r,q,p,o,n,m,l=this
t.bW.a(b)
s=b.length
if(s===0)return
r=l.a+s
q=l.b
p=q.length
if(p<r){o=r*2
if(o<1024)o=1024
else{n=o-1
n|=B.a.F(n,1)
n|=n>>>2
n|=n>>>4
n|=n>>>8
o=((n|n>>>16)>>>0)+1}m=new Uint8Array(o)
B.d.X(m,0,p,q)
l.b=m
q=m}B.d.X(q,l.a,r,b)
l.a=r},
ck(){var s=this
if(s.a===0)return $.fc()
return new Uint8Array(A.bo(J.dj(B.d.gG(s.b),s.b.byteOffset,s.a)))},
gk(a){return this.a},
J(a){this.a=0
this.b=$.fc()}}
A.b5.prototype={
i(a){return"LateInitializationError: "+this.a}}
A.cx.prototype={
gk(a){return this.a.length},
m(a,b){var s=this.a
if(!(b>=0&&b<s.length))return A.b(s,b)
return s.charCodeAt(b)}}
A.f6.prototype={
$0(){var s=new A.f($.h,t.D)
s.R(null)
return s},
$S:11}
A.dK.prototype={}
A.bD.prototype={}
A.bK.prototype={
gA(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s,r=this,q=r.a,p=J.bv(q),o=p.gk(q)
if(r.b!==o)throw A.a(A.b_(q))
s=r.c
if(s>=o){r.d=null
return!1}r.d=p.c5(q,s);++r.c
return!0},
$iau:1}
A.Q.prototype={}
A.aL.prototype={
t(a,b,c){A.B(this).h("aL.E").a(c)
throw A.a(A.bY("Cannot modify an unmodifiable list"))}}
A.bg.prototype={}
A.c8.prototype={$r:"+(1,2)",$s:1}
A.bB.prototype={
gaB(a){return this.gk(this)===0},
i(a){return A.fk(this)},
$ia8:1}
A.bC.prototype={
gk(a){return this.b.length},
bf(a){if("__proto__"===a)return!1
return this.a.hasOwnProperty(a)},
m(a,b){if(!this.bf(b))return null
return this.b[this.a[b]]},
N(a,b){var s,r,q,p,o=this
o.$ti.h("~(1,2)").a(b)
s=o.$keys
if(s==null){s=Object.keys(o.a)
o.$keys=s}s=s
r=o.b
for(q=s.length,p=0;p<q;++p)b.$2(s[p],r[p])}}
A.bS.prototype={}
A.dS.prototype={
E(a){var s,r,q=this,p=new RegExp(q.a).exec(a)
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
A.bP.prototype={
i(a){return"Null check operator used on a null value"}}
A.cI.prototype={
i(a){var s,r=this,q="NoSuchMethodError: method not found: '",p=r.b
if(p==null)return"NoSuchMethodError: "+r.a
s=r.c
if(s==null)return q+p+"' ("+r.a+")"
return q+p+"' on '"+s+"' ("+r.a+")"}}
A.cU.prototype={
i(a){var s=this.a
return s.length===0?"Error":"Error: "+s}}
A.dI.prototype={
i(a){return"Throw of null ('"+(this.a===null?"null":"undefined")+"' from JavaScript)"}}
A.bE.prototype={}
A.ca.prototype={
i(a){var s,r=this.b
if(r!=null)return r
r=this.a
s=r!==null&&typeof r==="object"?r.stack:null
return this.b=s==null?"":s},
$ia4:1}
A.aq.prototype={
i(a){var s=this.constructor,r=s==null?null:s.name
return"Closure '"+A.i_(r==null?"unknown":r)+"'"},
gl(a){var s=A.fH(this)
return A.a6(s==null?A.aV(this):s)},
$iaE:1,
gcp(){return this},
$C:"$1",
$R:1,
$D:null}
A.cv.prototype={$C:"$0",$R:0}
A.cw.prototype={$C:"$2",$R:2}
A.cS.prototype={}
A.cQ.prototype={
i(a){var s=this.$static_name
if(s==null)return"Closure of unknown static method"
return"Closure '"+A.i_(s)+"'"}}
A.aZ.prototype={
H(a,b){if(b==null)return!1
if(this===b)return!0
if(!(b instanceof A.aZ))return!1
return this.$_target===b.$_target&&this.a===b.a},
gp(a){return(A.hW(this.a)^A.bQ(this.$_target))>>>0},
i(a){return"Closure '"+this.$_name+"' of "+("Instance of '"+A.cN(this.a)+"'")}}
A.cP.prototype={
i(a){return"RuntimeError: "+this.a}}
A.aF.prototype={
gk(a){return this.a},
gaB(a){return this.a===0},
m(a,b){var s,r,q,p,o=null
if(typeof b=="string"){s=this.b
if(s==null)return o
r=s[b]
q=r==null?o:r.b
return q}else if(typeof b=="number"&&(b&0x3fffffff)===b){p=this.c
if(p==null)return o
r=p[b]
q=r==null?o:r.b
return q}else return this.ca(b)},
ca(a){var s,r,q=this.d
if(q==null)return null
s=q[this.bh(a)]
r=this.bi(s,a)
if(r<0)return null
return s[r].b},
t(a,b,c){var s,r,q,p,o,n,m=this,l=A.B(m)
l.c.a(b)
l.y[1].a(c)
if(typeof b=="string"){s=m.b
m.aJ(s==null?m.b=m.ak():s,b,c)}else if(typeof b=="number"&&(b&0x3fffffff)===b){r=m.c
m.aJ(r==null?m.c=m.ak():r,b,c)}else{q=m.d
if(q==null)q=m.d=m.ak()
p=m.bh(b)
o=q[p]
if(o==null)q[p]=[m.ae(b,c)]
else{n=m.bi(o,b)
if(n>=0)o[n].b=c
else o.push(m.ae(b,c))}}},
N(a,b){var s,r,q=this
A.B(q).h("~(1,2)").a(b)
s=q.e
r=q.r
while(s!=null){b.$2(s.a,s.b)
if(r!==q.r)throw A.a(A.b_(q))
s=s.c}},
aJ(a,b,c){var s,r=A.B(this)
r.c.a(b)
r.y[1].a(c)
s=a[b]
if(s==null)a[b]=this.ae(b,c)
else s.b=c},
ae(a,b){var s=this,r=A.B(s),q=new A.dy(r.c.a(a),r.y[1].a(b))
if(s.e==null)s.e=s.f=q
else s.f=s.f.c=q;++s.a
s.r=s.r+1&1073741823
return q},
bh(a){return J.T(a)&1073741823},
bi(a,b){var s,r
if(a==null)return-1
s=a.length
for(r=0;r<s;++r)if(J.di(a[r].a,b))return r
return-1},
i(a){return A.fk(this)},
ak(){var s=Object.create(null)
s["<non-identifier-key>"]=s
delete s["<non-identifier-key>"]
return s},
$ih_:1}
A.dy.prototype={}
A.dz.prototype={
gk(a){return this.a.a},
gK(a){var s=this.a
return new A.aG(s,s.r,s.e,this.$ti.h("aG<1>"))}}
A.aG.prototype={
gA(){return this.d},
n(){var s,r=this,q=r.a
if(r.b!==q.r)throw A.a(A.b_(q))
s=r.c
if(s==null){r.d=null
return!1}else{r.d=s.a
r.c=s.c
return!0}},
$iau:1}
A.f1.prototype={
$1(a){return this.a(a)},
$S:7}
A.f2.prototype={
$2(a,b){return this.a(a,b)},
$S:12}
A.f3.prototype={
$1(a){return this.a(A.al(a))},
$S:13}
A.aQ.prototype={
gl(a){return A.a6(this.aW())},
aW(){return A.kv(this.$r,this.aV())},
i(a){return this.b7(!1)},
b7(a){var s,r,q,p,o,n=this.bJ(),m=this.aV(),l=(a?"Record ":"")+"("
for(s=n.length,r="",q=0;q<s;++q,r=", "){l+=r
p=n[q]
if(typeof p=="string")l=l+p+": "
if(!(q<m.length))return A.b(m,q)
o=m[q]
l=a?l+A.h7(o):l+A.o(o)}l+=")"
return l.charCodeAt(0)==0?l:l},
bJ(){var s,r=this.$s
while($.ey.length<=r)B.b.j($.ey,null)
s=$.ey[r]
if(s==null){s=this.bF()
B.b.t($.ey,r,s)}return s},
bF(){var s,r,q,p=this.$r,o=p.indexOf("("),n=p.substring(1,o),m=p.substring(o),l=m==="()"?0:m.replace(/[^,]/g,"").length+1,k=A.i(new Array(l),t.f)
for(s=0;s<l;++s)k[s]=s
if(n!==""){r=n.split(",")
s=r.length
for(q=l;s>0;){--q;--s
B.b.t(k,q,r[s])}}k=A.fj(k,!1,t.K)
k.$flags=3
return k}}
A.bl.prototype={
aV(){return[this.a,this.b]},
H(a,b){if(b==null)return!1
return b instanceof A.bl&&this.$s===b.$s&&J.di(this.a,b.a)&&J.di(this.b,b.b)},
gp(a){return A.h3(this.$s,this.a,this.b,B.e,B.e)}}
A.e8.prototype={}
A.aw.prototype={
gaa(a){return a.byteLength},
gl(a){return B.aL},
a6(a,b,c){A.aR(a,b,c)
return c==null?new Uint8Array(a,b):new Uint8Array(a,b,c)},
bb(a,b){return this.a6(a,b,null)},
ba(a,b,c){A.aR(a,b,c)
return new Int32Array(a,b,c)},
b9(a,b,c){A.aR(a,b,c)
return new Float32Array(a,b,c)},
b8(a,b,c){var s
A.aR(a,b,c)
s=new DataView(a,b,c)
return s},
$il:1,
$iaw:1,
$ibA:1}
A.b6.prototype={$ib6:1}
A.bO.prototype={
gG(a){if(((a.$flags|0)&2)!==0)return new A.d8(a.buffer)
else return a.buffer},
bM(a,b,c,d){var s=A.ad(b,0,c,d,null)
throw A.a(s)},
aQ(a,b,c,d){if(b>>>0!==b||b>c)this.bM(a,b,c,d)},
$it:1}
A.d8.prototype={
gaa(a){return this.a.byteLength},
a6(a,b,c){var s=A.iJ(this.a,b,c)
s.$flags=3
return s},
bb(a,b){return this.a6(0,b,null)},
ba(a,b,c){var s=A.iH(this.a,b,c)
s.$flags=3
return s},
b9(a,b,c){var s=A.iG(this.a,b,c)
s.$flags=3
return s},
b8(a,b,c){var s=A.iF(this.a,b,c)
s.$flags=3
return s},
$ibA:1}
A.aI.prototype={
gl(a){return B.aM},
$il:1,
$iaI:1,
$idm:1}
A.H.prototype={
gk(a){return a.length},
b2(a,b,c,d,e){var s,r,q=a.length
this.aQ(a,b,q,"start")
this.aQ(a,c,q,"end")
if(b>c)throw A.a(A.ad(b,0,c,null,null))
s=c-b
if(e<0)throw A.a(A.by(e,null))
r=d.length
if(r-e<s)throw A.a(A.a9("Not enough elements"))
if(e!==0||r!==s)d=d.subarray(e,e+s)
a.set(d,b)},
$iV:1}
A.bN.prototype={
m(a,b){A.am(b,a,a.length)
return a[b]},
t(a,b,c){A.da(c)
a.$flags&2&&A.K(a)
A.am(b,a,a.length)
a[b]=c},
Y(a,b,c,d,e){t.bM.a(d)
a.$flags&2&&A.K(a,5)
this.b2(a,b,c,d,e)
return},
$ie:1,
$ij:1}
A.W.prototype={
t(a,b,c){A.u(c)
a.$flags&2&&A.K(a)
A.am(b,a,a.length)
a[b]=c},
X(a,b,c,d){t.hb.a(d)
a.$flags&2&&A.K(a,5)
if(t.eB.b(d)){this.b2(a,b,c,d,0)
return}this.bx(a,b,c,d,0)},
$ie:1,
$ij:1}
A.aJ.prototype={
gl(a){return B.aN},
$il:1,
$iaJ:1,
$idq:1}
A.b7.prototype={
gl(a){return B.aO},
$il:1,
$ib7:1,
$idr:1}
A.b8.prototype={
gl(a){return B.aP},
m(a,b){A.am(b,a,a.length)
return a[b]},
$il:1,
$ib8:1,
$idt:1}
A.b9.prototype={
gl(a){return B.aQ},
m(a,b){A.am(b,a,a.length)
return a[b]},
$il:1,
$ib9:1,
$idu:1}
A.ba.prototype={
gl(a){return B.aR},
m(a,b){A.am(b,a,a.length)
return a[b]},
$il:1,
$iba:1,
$idv:1}
A.bb.prototype={
gl(a){return B.aU},
m(a,b){A.am(b,a,a.length)
return a[b]},
$il:1,
$ibb:1,
$idU:1}
A.bc.prototype={
gl(a){return B.aV},
m(a,b){A.am(b,a,a.length)
return a[b]},
$il:1,
$ibc:1,
$idV:1}
A.aK.prototype={
gl(a){return B.aW},
gk(a){return a.length},
m(a,b){A.am(b,a,a.length)
return a[b]},
$il:1,
$iaK:1,
$idW:1}
A.ax.prototype={
gl(a){return B.aX},
gk(a){return a.length},
m(a,b){A.am(b,a,a.length)
return a[b]},
aI(a,b,c){return new Uint8Array(a.subarray(b,A.jq(b,c,a.length)))},
$il:1,
$iax:1,
$ibV:1}
A.c4.prototype={}
A.c5.prototype={}
A.c6.prototype={}
A.c7.prototype={}
A.a3.prototype={
h(a){return A.ci(v.typeUniverse,this,a)},
C(a){return A.hw(v.typeUniverse,this,a)}}
A.d3.prototype={}
A.eE.prototype={
i(a){return A.O(this.a,null)}}
A.d2.prototype={
i(a){return this.a}}
A.ce.prototype={$iaf:1}
A.e4.prototype={
$1(a){var s=this.a,r=s.a
s.a=null
r.$0()},
$S:8}
A.e3.prototype={
$1(a){var s,r
this.a.a=t.M.a(a)
s=this.b
r=this.c
s.firstChild?s.removeChild(r):s.appendChild(r)},
$S:14}
A.e5.prototype={
$0(){this.a.$0()},
$S:2}
A.e6.prototype={
$0(){this.a.$0()},
$S:2}
A.eC.prototype={
by(a,b){if(self.setTimeout!=null)this.b=self.setTimeout(A.bt(new A.eD(this,b),0),a)
else throw A.a(A.bY("`setTimeout()` not found."))},
av(){if(self.setTimeout!=null){var s=this.b
if(s==null)return
self.clearTimeout(s)
this.b=null}else throw A.a(A.bY("Canceling a timer."))}}
A.eD.prototype={
$0(){this.a.b=null
this.b.$0()},
$S:0}
A.c_.prototype={
a7(a){var s,r=this,q=r.$ti
q.h("1/?").a(a)
if(a==null)a=q.c.a(a)
if(!r.b)r.a.R(a)
else{s=r.a
if(q.h("L<1>").b(a))s.aP(a)
else s.ah(a)}},
az(a,b){var s=this.a
if(this.b)s.M(new A.G(a,b))
else s.S(new A.G(a,b))},
$idp:1}
A.eM.prototype={
$1(a){return this.a.$2(0,a)},
$S:3}
A.eN.prototype={
$2(a,b){this.a.$2(1,new A.bE(a,t.l.a(b)))},
$S:15}
A.eU.prototype={
$2(a,b){this.a(A.u(a),b)},
$S:16}
A.E.prototype={
gA(){var s=this.b
return s==null?this.$ti.c.a(s):s},
bU(a,b){var s,r,q
a=A.u(a)
b=b
s=this.a
for(;;)try{r=s(this,a,b)
return r}catch(q){b=q
a=1}},
n(){var s,r,q,p,o=this,n=null,m=0
for(;;){s=o.d
if(s!=null)try{if(s.n()){o.b=s.gA()
return!0}else o.d=null}catch(r){n=r
m=1
o.d=null}q=o.bU(m,n)
if(1===q)return!0
if(0===q){o.b=null
p=o.e
if(p==null||p.length===0){o.a=A.hr
return!1}if(0>=p.length)return A.b(p,-1)
o.a=p.pop()
m=0
n=null
continue}if(2===q){m=0
n=null
continue}if(3===q){n=o.c
o.c=null
p=o.e
if(p==null||p.length===0){o.b=null
o.a=A.hr
throw n
return!1}if(0>=p.length)return A.b(p,-1)
o.a=p.pop()
m=1
continue}throw A.a(A.a9("sync*"))}return!1},
cs(a){var s,r,q=this
if(a instanceof A.bn){s=a.a()
r=q.e
if(r==null)r=q.e=[]
B.b.j(r,q.a)
q.a=s
return 2}else{q.d=J.cr(a)
return 2}},
$iau:1}
A.bn.prototype={
gK(a){return new A.E(this.a(),this.$ti.h("E<1>"))}}
A.G.prototype={
i(a){return A.o(this.a)},
$in:1,
gP(){return this.b}}
A.ds.prototype={
$0(){this.c.a(null)
this.b.ag(null)},
$S:0}
A.c1.prototype={
az(a,b){var s=this.a
if((s.a&30)!==0)throw A.a(A.a9("Future already completed"))
s.S(A.jC(a,b))},
be(a){return this.az(a,null)},
$idp:1}
A.ai.prototype={
a7(a){var s,r=this.$ti
r.h("1/?").a(a)
s=this.a
if((s.a&30)!==0)throw A.a(A.a9("Future already completed"))
s.R(r.h("1/").a(a))},
bd(){return this.a7(null)}}
A.aj.prototype={
cc(a){if((this.c&15)!==6)return!0
return this.b.b.aF(t.al.a(this.d),a.a,t.y,t.K)},
c8(a){var s,r=this,q=r.e,p=null,o=t.z,n=t.K,m=a.a,l=r.b.b
if(t.Q.b(q))p=l.cf(q,m,a.b,o,n,t.l)
else p=l.aF(t.v.a(q),m,o,n)
try{o=r.$ti.h("2/").a(p)
return o}catch(s){if(t.eK.b(A.P(s))){if((r.c&1)!==0)throw A.a(A.by("The error handler of Future.then must return a value of the returned future's type","onError"))
throw A.a(A.by("The error handler of Future.catchError must return a value of the future's type","onError"))}else throw s}}}
A.f.prototype={
W(a,b,c){var s,r,q,p=this.$ti
p.C(c).h("1/(2)").a(a)
s=$.h
if(s===B.c){if(b!=null&&!t.Q.b(b)&&!t.v.b(b))throw A.a(A.aC(b,"onError",u.c))}else{c.h("@<0/>").C(p.c).h("1(2)").a(a)
if(b!=null)b=A.k2(b,s)}r=new A.f(s,c.h("f<0>"))
q=b==null?1:3
this.a_(new A.aj(r,q,a,b,p.h("@<1>").C(c).h("aj<1,2>")))
return r},
ci(a,b){return this.W(a,null,b)},
b6(a,b,c){var s,r=this.$ti
r.C(c).h("1/(2)").a(a)
s=new A.f($.h,c.h("f<0>"))
this.a_(new A.aj(s,19,a,b,r.h("@<1>").C(c).h("aj<1,2>")))
return s},
aH(a){var s,r
t.O.a(a)
s=this.$ti
r=new A.f($.h,s)
this.a_(new A.aj(r,8,a,null,s.h("aj<1,1>")))
return r},
bV(a){this.a=this.a&1|16
this.c=a},
a1(a){this.a=a.a&30|this.a&1
this.c=a.c},
a_(a){var s,r=this,q=r.a
if(q<=3){a.a=t.F.a(r.c)
r.c=a}else{if((q&4)!==0){s=t._.a(r.c)
if((s.a&24)===0){s.a_(a)
return}r.a1(s)}A.bq(null,null,r.b,t.M.a(new A.ee(r,a)))}},
b1(a){var s,r,q,p,o,n,m=this,l={}
l.a=a
if(a==null)return
s=m.a
if(s<=3){r=t.F.a(m.c)
m.c=a
if(r!=null){q=a.a
for(p=a;q!=null;p=q,q=o)o=q.a
p.a=r}}else{if((s&4)!==0){n=t._.a(m.c)
if((n.a&24)===0){n.b1(a)
return}m.a1(n)}l.a=m.a2(a)
A.bq(null,null,m.b,t.M.a(new A.ej(l,m)))}},
T(){var s=t.F.a(this.c)
this.c=null
return this.a2(s)},
a2(a){var s,r,q
for(s=a,r=null;s!=null;r=s,s=q){q=s.a
s.a=r}return r},
ag(a){var s,r=this,q=r.$ti
q.h("1/").a(a)
if(q.h("L<1>").b(a))A.eh(a,r,!0)
else{s=r.T()
q.c.a(a)
r.a=8
r.c=a
A.aO(r,s)}},
ah(a){var s,r=this
r.$ti.c.a(a)
s=r.T()
r.a=8
r.c=a
A.aO(r,s)},
bE(a){var s,r,q=this
if((a.a&16)!==0){s=q.b===a.b
s=!(s||s)}else s=!1
if(s)return
r=q.T()
q.a1(a)
A.aO(q,r)},
M(a){var s=this.T()
this.bV(a)
A.aO(this,s)},
bD(a,b){A.a0(a)
t.l.a(b)
this.M(new A.G(a,b))},
R(a){var s=this.$ti
s.h("1/").a(a)
if(s.h("L<1>").b(a)){this.aP(a)
return}this.bB(a)},
bB(a){var s=this
s.$ti.c.a(a)
s.a^=2
A.bq(null,null,s.b,t.M.a(new A.eg(s,a)))},
aP(a){A.eh(this.$ti.h("L<1>").a(a),this,!1)
return},
S(a){this.a^=2
A.bq(null,null,this.b,t.M.a(new A.ef(this,a)))},
cj(a,b){var s,r,q=this,p={},o=q.$ti
o.h("1/()?").a(b)
if((q.a&24)!==0){p=new A.f($.h,o)
p.R(q)
return p}s=$.h
r=new A.f(s,o)
p.a=null
p.a=A.hf(a,new A.ep(q,r,s,o.h("1/()").a(b)))
q.W(new A.eq(p,q,r),new A.er(p,r),t.P)
return r},
$iL:1}
A.ee.prototype={
$0(){A.aO(this.a,this.b)},
$S:0}
A.ej.prototype={
$0(){A.aO(this.b,this.a.a)},
$S:0}
A.ei.prototype={
$0(){A.eh(this.a.a,this.b,!0)},
$S:0}
A.eg.prototype={
$0(){this.a.ah(this.b)},
$S:0}
A.ef.prototype={
$0(){this.a.M(this.b)},
$S:0}
A.em.prototype={
$0(){var s,r,q,p,o,n,m,l,k=this,j=null
try{q=k.a.a
j=q.b.b.aE(t.O.a(q.d),t.z)}catch(p){s=A.P(p)
r=A.S(p)
if(k.c&&t.n.a(k.b.a.c).a===s){q=k.a
q.c=t.n.a(k.b.a.c)}else{q=s
o=r
if(o==null)o=A.cu(q)
n=k.a
n.c=new A.G(q,o)
q=n}q.b=!0
return}if(j instanceof A.f&&(j.a&24)!==0){if((j.a&16)!==0){q=k.a
q.c=t.n.a(j.c)
q.b=!0}return}if(j instanceof A.f){m=k.b.a
l=new A.f(m.b,m.$ti)
j.W(new A.en(l,m),new A.eo(l),t.H)
q=k.a
q.c=l
q.b=!1}},
$S:0}
A.en.prototype={
$1(a){this.a.bE(this.b)},
$S:8}
A.eo.prototype={
$2(a,b){A.a0(a)
t.l.a(b)
this.a.M(new A.G(a,b))},
$S:4}
A.el.prototype={
$0(){var s,r,q,p,o,n,m,l
try{q=this.a
p=q.a
o=p.$ti
n=o.c
m=n.a(this.b)
q.c=p.b.b.aF(o.h("2/(1)").a(p.d),m,o.h("2/"),n)}catch(l){s=A.P(l)
r=A.S(l)
q=s
p=r
if(p==null)p=A.cu(q)
o=this.a
o.c=new A.G(q,p)
o.b=!0}},
$S:0}
A.ek.prototype={
$0(){var s,r,q,p,o,n,m,l=this
try{s=t.n.a(l.a.a.c)
p=l.b
if(p.a.cc(s)&&p.a.e!=null){p.c=p.a.c8(s)
p.b=!1}}catch(o){r=A.P(o)
q=A.S(o)
p=t.n.a(l.a.a.c)
if(p.a===r){n=l.b
n.c=p
p=n}else{p=r
n=q
if(n==null)n=A.cu(p)
m=l.b
m.c=new A.G(p,n)
p=m}p.b=!0}},
$S:0}
A.ep.prototype={
$0(){var s,r,q,p,o,n=this
try{n.b.ag(n.c.aE(n.d,n.a.$ti.h("1/")))}catch(q){s=A.P(q)
r=A.S(q)
p=s
o=r
if(o==null)o=A.cu(p)
n.b.M(new A.G(p,o))}},
$S:0}
A.eq.prototype={
$1(a){var s
this.b.$ti.c.a(a)
s=this.a.a
if(s.b!=null){s.av()
this.c.ah(a)}},
$S(){return this.b.$ti.h("r(1)")}}
A.er.prototype={
$2(a,b){var s
A.a0(a)
t.l.a(b)
s=this.a.a
if(s.b!=null){s.av()
this.b.M(new A.G(a,b))}},
$S:4}
A.cX.prototype={}
A.bU.prototype={
gk(a){var s={},r=new A.f($.h,t.fJ)
s.a=0
this.bk(new A.dP(s,this),!0,new A.dQ(s,r),r.gbC())
return r}}
A.dP.prototype={
$1(a){this.b.$ti.c.a(a);++this.a.a},
$S(){return this.b.$ti.h("~(1)")}}
A.dQ.prototype={
$0(){this.b.ag(this.a.a)},
$S:0}
A.cb.prototype={
gbR(){var s,r=this
if((r.b&8)===0)return A.B(r).h("a5<1>?").a(r.a)
s=A.B(r)
return s.h("a5<1>?").a(s.h("cc<1>").a(r.a).gap())},
aT(){var s,r,q=this
if((q.b&8)===0){s=q.a
if(s==null)s=q.a=new A.a5(A.B(q).h("a5<1>"))
return A.B(q).h("a5<1>").a(s)}r=A.B(q)
s=r.h("cc<1>").a(q.a).gap()
return r.h("a5<1>").a(s)},
gb4(){var s=this.a
if((this.b&8)!==0)s=t.fv.a(s).gap()
return A.B(this).h("bk<1>").a(s)},
aN(){if((this.b&4)!==0)return new A.ay("Cannot add event after closing")
return new A.ay("Cannot add event while adding a stream")},
aS(){var s=this.c
if(s==null)s=this.c=(this.b&2)!==0?$.fb():new A.f($.h,t.D)
return s},
j(a,b){var s,r=this,q=A.B(r)
q.c.a(b)
s=r.b
if(s>=4)throw A.a(r.aN())
if((s&1)!==0)r.an(b)
else if((s&3)===0)r.aT().j(0,new A.aM(b,q.h("aM<1>")))},
q(){var s=this,r=s.b
if((r&4)!==0)return s.aS()
if(r>=4)throw A.a(s.aN())
r=s.b=r|4
if((r&1)!==0)s.ao()
else if((r&3)===0)s.aT().j(0,B.w)
return s.aS()},
bY(a,b,c,d){var s,r,q,p,o,n,m,l=this,k=A.B(l)
k.h("~(1)?").a(a)
t.d.a(c)
if((l.b&3)!==0)throw A.a(A.a9("Stream has already been listened to."))
s=$.h
r=d?1:0
q=b!=null?32:0
t.r.C(k.c).h("1(2)").a(a)
A.iY(s,b)
p=t.M
o=new A.bk(l,a,p.a(c),s,r|q,k.h("bk<1>"))
n=l.gbR()
if(((l.b|=1)&8)!==0){m=k.h("cc<1>").a(l.a)
m.sap(o)
m.ce()}else l.a=o
o.bW(n)
k=p.a(new A.eB(l))
s=o.e
o.e=s|64
k.$0()
o.e&=4294967231
o.aR((s&4)!==0)
return o},
bS(a){var s,r,q,p,o,n,m,l,k=this,j=A.B(k)
j.h("cR<1>").a(a)
s=null
if((k.b&8)!==0)s=j.h("cc<1>").a(k.a).av()
k.a=null
k.b=k.b&4294967286|2
r=k.r
if(r!=null)if(s==null)try{q=r.$0()
if(q instanceof A.f)s=q}catch(n){p=A.P(n)
o=A.S(n)
m=new A.f($.h,t.D)
j=A.a0(p)
l=t.l.a(o)
m.S(new A.G(j,l))
s=m}else s=s.aH(r)
j=new A.eA(k)
if(s!=null)s=s.aH(j)
else j.$0()
return s},
$ihb:1,
$ihq:1,
$iaN:1}
A.eB.prototype={
$0(){A.fC(this.a.d)},
$S:0}
A.eA.prototype={
$0(){var s=this.a.c
if(s!=null&&(s.a&30)===0)s.R(null)},
$S:0}
A.cY.prototype={
an(a){var s=this.$ti
s.c.a(a)
this.gb4().aL(new A.aM(a,s.h("aM<1>")))},
ao(){this.gb4().aL(B.w)}}
A.bi.prototype={}
A.bj.prototype={
gp(a){return(A.bQ(this.a)^892482866)>>>0},
H(a,b){if(b==null)return!1
if(this===b)return!0
return b instanceof A.bj&&b.a===this.a}}
A.bk.prototype={
aY(){return this.w.bS(this)},
aZ(){var s=this.w,r=A.B(s)
r.h("cR<1>").a(this)
if((s.b&8)!==0)r.h("cc<1>").a(s.a).ct()
A.fC(s.e)},
b_(){var s=this.w,r=A.B(s)
r.h("cR<1>").a(this)
if((s.b&8)!==0)r.h("cc<1>").a(s.a).ce()
A.fC(s.f)}}
A.c0.prototype={
bW(a){var s=this
A.B(s).h("a5<1>?").a(a)
if(a==null)return
s.r=a
if(a.c!=null){s.e|=128
a.ad(s)}},
aO(){var s,r=this,q=r.e|=8
if((q&128)!==0){s=r.r
if(s.a===1)s.a=3}if((q&64)===0)r.r=null
r.f=r.aY()},
aZ(){},
b_(){},
aY(){return null},
aL(a){var s,r=this,q=r.r
if(q==null)q=r.r=new A.a5(A.B(r).h("a5<1>"))
q.j(0,a)
s=r.e
if((s&128)===0){s|=128
r.e=s
if(s<256)q.ad(r)}},
an(a){var s,r=this,q=A.B(r).c
q.a(a)
s=r.e
r.e=s|64
r.d.cg(r.a,a,q)
r.e&=4294967231
r.aR((s&4)!==0)},
ao(){var s,r=this,q=new A.e7(r)
r.aO()
r.e|=16
s=r.f
if(s!=null&&s!==$.fb())s.aH(q)
else q.$0()},
aR(a){var s,r,q=this,p=q.e
if((p&128)!==0&&q.r.c==null){p=q.e=p&4294967167
s=!1
if((p&4)!==0)if(p<256){s=q.r
s=s==null?null:s.c==null
s=s!==!1}if(s){p&=4294967291
q.e=p}}for(;;a=r){if((p&8)!==0){q.r=null
return}r=(p&4)!==0
if(a===r)break
q.e=p^64
if(r)q.aZ()
else q.b_()
p=q.e&=4294967231}if((p&128)!==0&&p<256)q.r.ad(q)},
$icR:1,
$iaN:1}
A.e7.prototype={
$0(){var s=this.a,r=s.e
if((r&16)===0)return
s.e=r|74
s.d.bm(s.c)
s.e&=4294967231},
$S:0}
A.cd.prototype={
bk(a,b,c,d){var s=this.$ti
s.h("~(1)?").a(a)
t.d.a(c)
return this.a.bY(s.h("~(1)?").a(a),d,c,b===!0)},
cb(a,b){return this.bk(a,null,b,null)}}
A.az.prototype={
sV(a){this.a=t.ev.a(a)},
gV(){return this.a}}
A.aM.prototype={
bl(a){this.$ti.h("aN<1>").a(a).an(this.b)}}
A.d0.prototype={
bl(a){a.ao()},
gV(){return null},
sV(a){throw A.a(A.a9("No events after a done."))},
$iaz:1}
A.a5.prototype={
ad(a){var s,r=this
r.$ti.h("aN<1>").a(a)
s=r.a
if(s===1)return
if(s>=1){r.a=1
return}A.kN(new A.ex(r,a))
r.a=1},
j(a,b){var s=this,r=s.c
if(r==null)s.b=s.c=b
else{r.sV(b)
s.c=b}}}
A.ex.prototype={
$0(){var s,r,q,p=this.a,o=p.a
p.a=0
if(o===3)return
s=p.$ti.h("aN<1>").a(this.b)
r=p.b
q=r.gV()
p.b=q
if(q==null)p.c=null
r.bl(s)},
$S:0}
A.d6.prototype={}
A.ck.prototype={$ihi:1}
A.d5.prototype={
bm(a){var s,r,q
t.M.a(a)
try{if(B.c===$.h){a.$0()
return}A.hM(null,null,this,a,t.H)}catch(q){s=A.P(q)
r=A.S(q)
A.dd(A.a0(s),t.l.a(r))}},
cg(a,b,c){var s,r,q
c.h("~(0)").a(a)
c.a(b)
try{if(B.c===$.h){a.$1(b)
return}A.hN(null,null,this,a,b,t.H,c)}catch(q){s=A.P(q)
r=A.S(q)
A.dd(A.a0(s),t.l.a(r))}},
au(a){return new A.ez(this,t.M.a(a))},
aE(a,b){b.h("0()").a(a)
if($.h===B.c)return a.$0()
return A.hM(null,null,this,a,b)},
aF(a,b,c,d){c.h("@<0>").C(d).h("1(2)").a(a)
d.a(b)
if($.h===B.c)return a.$1(b)
return A.hN(null,null,this,a,b,c,d)},
cf(a,b,c,d,e,f){d.h("@<0>").C(e).C(f).h("1(2,3)").a(a)
e.a(b)
f.a(c)
if($.h===B.c)return a.$2(b,c)
return A.k4(null,null,this,a,b,c,d,e,f)},
aD(a,b,c,d){return b.h("@<0>").C(c).C(d).h("1(2,3)").a(a)}}
A.ez.prototype={
$0(){return this.a.bm(this.b)},
$S:0}
A.eR.prototype={
$0(){A.iq(this.a,this.b)},
$S:0}
A.c2.prototype={
gK(a){var s=this,r=new A.c3(s,s.r,s.$ti.h("c3<1>"))
r.c=s.e
return r},
gk(a){return this.a},
c2(a,b){var s
if((b&1073741823)===b){s=this.c
if(s==null)return!1
return t.L.a(s[b])!=null}else return this.bG(b)},
bG(a){var s=this.d
if(s==null)return!1
return this.aU(s[B.a.gp(a)&1073741823],a)>=0},
j(a,b){var s,r,q=this
q.$ti.c.a(b)
if(typeof b=="string"&&b!=="__proto__"){s=q.b
return q.aK(s==null?q.b=A.fq():s,b)}else if(typeof b=="number"&&(b&1073741823)===b){r=q.c
return q.aK(r==null?q.c=A.fq():r,b)}else return q.bz(b)},
bz(a){var s,r,q,p=this
p.$ti.c.a(a)
s=p.d
if(s==null)s=p.d=A.fq()
r=J.T(a)&1073741823
q=s[r]
if(q==null)s[r]=[p.al(a)]
else{if(p.aU(q,a)>=0)return!1
q.push(p.al(a))}return!0},
aK(a,b){this.$ti.c.a(b)
if(t.L.a(a[b])!=null)return!1
a[b]=this.al(b)
return!0},
al(a){var s=this,r=new A.d4(s.$ti.c.a(a))
if(s.e==null)s.e=s.f=r
else s.f=s.f.b=r;++s.a
s.r=s.r+1&1073741823
return r},
aU(a,b){var s,r
if(a==null)return-1
s=a.length
for(r=0;r<s;++r)if(J.di(a[r].a,b))return r
return-1}}
A.d4.prototype={}
A.c3.prototype={
gA(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s=this,r=s.c,q=s.a
if(s.b!==q.r)throw A.a(A.b_(q))
else if(r==null){s.d=null
return!1}else{s.d=s.$ti.h("1?").a(r.a)
s.c=r.b
return!0}},
$iau:1}
A.k.prototype={
gK(a){return new A.bK(a,this.gk(a),A.aV(a).h("bK<k.E>"))},
c5(a,b){return this.m(a,b)},
gbj(a){return this.gk(a)!==0},
Y(a,b,c,d,e){var s,r,q
A.aV(a).h("e<k.E>").a(d)
A.cO(b,c,this.gk(a))
s=c-b
if(s===0)return
A.h9(e,"skipCount")
r=J.bv(d)
if(e+s>r.gk(d))throw A.a(A.a9("Too few elements"))
if(e<b)for(q=s-1;q>=0;--q)this.t(a,b+q,r.m(d,e+q))
else for(q=0;q<s;++q)this.t(a,b+q,r.m(d,e+q))},
i(a){return A.ff(a,"[","]")},
$ie:1,
$ij:1}
A.bL.prototype={
N(a,b){var s,r,q,p=this,o=A.B(p)
o.h("~(1,2)").a(b)
for(s=new A.aG(p,p.r,p.e,o.h("aG<1>")),o=o.y[1];s.n();){r=s.d
q=p.m(0,r)
b.$2(r,q==null?o.a(q):q)}},
gk(a){return this.a},
gaB(a){return this.a===0},
i(a){return A.fk(this)},
$ia8:1}
A.dA.prototype={
$2(a,b){var s,r=this.a
if(!r.a)this.b.a+=", "
r.a=!1
r=this.b
s=A.o(a)
r.a=(r.a+=s)+": "
s=A.o(b)
r.a+=s},
$S:1}
A.be.prototype={
i(a){return A.ff(this,"{","}")},
$ie:1}
A.c9.prototype={}
A.cy.prototype={}
A.cA.prototype={}
A.bJ.prototype={
i(a){var s=A.cB(this.a)
return(this.b!=null?"Converting object to an encodable object failed:":"Converting object did not return an encodable object:")+" "+s}}
A.cK.prototype={
i(a){return"Cyclic error in JSON stringify"}}
A.cJ.prototype={
c6(a,b){var s=A.j0(a,this.gc7().b,null)
return s},
gc7(){return B.ay}}
A.dx.prototype={}
A.eu.prototype={
bq(a){var s,r,q,p,o,n,m=a.length
for(s=this.c,r=0,q=0;q<m;++q){p=a.charCodeAt(q)
if(p>92){if(p>=55296){o=p&64512
if(o===55296){n=q+1
n=!(n<m&&(a.charCodeAt(n)&64512)===56320)}else n=!1
if(!n)if(o===56320){o=q-1
o=!(o>=0&&(a.charCodeAt(o)&64512)===55296)}else o=!1
else o=!0
if(o){if(q>r)s.a+=B.h.Z(a,r,q)
r=q+1
o=A.I(92)
s.a+=o
o=A.I(117)
s.a+=o
o=A.I(100)
s.a+=o
o=p>>>8&15
o=A.I(o<10?48+o:87+o)
s.a+=o
o=p>>>4&15
o=A.I(o<10?48+o:87+o)
s.a+=o
o=p&15
o=A.I(o<10?48+o:87+o)
s.a+=o}}continue}if(p<32){if(q>r)s.a+=B.h.Z(a,r,q)
r=q+1
o=A.I(92)
s.a+=o
switch(p){case 8:o=A.I(98)
s.a+=o
break
case 9:o=A.I(116)
s.a+=o
break
case 10:o=A.I(110)
s.a+=o
break
case 12:o=A.I(102)
s.a+=o
break
case 13:o=A.I(114)
s.a+=o
break
default:o=A.I(117)
s.a+=o
o=A.I(48)
s.a=(s.a+=o)+o
o=p>>>4&15
o=A.I(o<10?48+o:87+o)
s.a+=o
o=p&15
o=A.I(o<10?48+o:87+o)
s.a+=o
break}}else if(p===34||p===92){if(q>r)s.a+=B.h.Z(a,r,q)
r=q+1
o=A.I(92)
s.a+=o
o=A.I(p)
s.a+=o}}if(r===0)s.a+=a
else if(r<m)s.a+=B.h.Z(a,r,m)},
af(a){var s,r,q,p
for(s=this.a,r=s.length,q=0;q<r;++q){p=s[q]
if(a==null?p==null:a===p)throw A.a(new A.cK(a,null))}B.b.j(s,a)},
ab(a){var s,r,q,p,o=this
if(o.bp(a))return
o.af(a)
try{s=o.b.$1(a)
if(!o.bp(s)){q=A.fZ(a,null,o.gb0())
throw A.a(q)}q=o.a
if(0>=q.length)return A.b(q,-1)
q.pop()}catch(p){r=A.P(p)
q=A.fZ(a,r,o.gb0())
throw A.a(q)}},
bp(a){var s,r,q=this
if(typeof a=="number"){if(!isFinite(a))return!1
q.c.a+=B.l.i(a)
return!0}else if(a===!0){q.c.a+="true"
return!0}else if(a===!1){q.c.a+="false"
return!0}else if(a==null){q.c.a+="null"
return!0}else if(typeof a=="string"){s=q.c
s.a+='"'
q.bq(a)
s.a+='"'
return!0}else if(t.j.b(a)){q.af(a)
q.cn(a)
s=q.a
if(0>=s.length)return A.b(s,-1)
s.pop()
return!0}else if(t.G.b(a)){q.af(a)
r=q.co(a)
s=q.a
if(0>=s.length)return A.b(s,-1)
s.pop()
return r}else return!1},
cn(a){var s,r,q=this.c
q.a+="["
s=J.hT(a)
if(s.gbj(a)){this.ab(s.m(a,0))
for(r=1;r<s.gk(a);++r){q.a+=","
this.ab(s.m(a,r))}}q.a+="]"},
co(a){var s,r,q,p,o,n,m=this,l={}
if(a.gaB(a)){m.c.a+="{}"
return!0}s=a.gk(a)*2
r=A.aH(s,null,!1,t.X)
q=l.a=0
l.b=!0
a.N(0,new A.ev(l,r))
if(!l.b)return!1
p=m.c
p.a+="{"
for(o='"';q<s;q+=2,o=',"'){p.a+=o
m.bq(A.al(r[q]))
p.a+='":'
n=q+1
if(!(n<s))return A.b(r,n)
m.ab(r[n])}p.a+="}"
return!0}}
A.ev.prototype={
$2(a,b){var s,r
if(typeof a!="string")this.a.b=!1
s=this.b
r=this.a
B.b.t(s,r.a++,a)
B.b.t(s,r.a++,b)},
$S:1}
A.et.prototype={
gb0(){var s=this.c.a
return s.charCodeAt(0)==0?s:s}}
A.dX.prototype={
a8(a){var s,r,q,p=a.length,o=A.cO(0,null,p)
if(o===0)return new Uint8Array(0)
s=new Uint8Array(o*3)
r=new A.eG(s)
if(r.bK(a,0,o)!==o){q=o-1
if(!(q>=0&&q<p))return A.b(a,q)
r.ar()}return B.d.aI(s,0,r.b)}}
A.eG.prototype={
ar(){var s,r=this,q=r.c,p=r.b,o=r.b=p+1
q.$flags&2&&A.K(q)
s=q.length
if(!(p<s))return A.b(q,p)
q[p]=239
p=r.b=o+1
if(!(o<s))return A.b(q,o)
q[o]=191
r.b=p+1
if(!(p<s))return A.b(q,p)
q[p]=189},
bZ(a,b){var s,r,q,p,o,n=this
if((b&64512)===56320){s=65536+((a&1023)<<10)|b&1023
r=n.c
q=n.b
p=n.b=q+1
r.$flags&2&&A.K(r)
o=r.length
if(!(q<o))return A.b(r,q)
r[q]=s>>>18|240
q=n.b=p+1
if(!(p<o))return A.b(r,p)
r[p]=s>>>12&63|128
p=n.b=q+1
if(!(q<o))return A.b(r,q)
r[q]=s>>>6&63|128
n.b=p+1
if(!(p<o))return A.b(r,p)
r[p]=s&63|128
return!0}else{n.ar()
return!1}},
bK(a,b,c){var s,r,q,p,o,n,m,l,k=this
if(b!==c){s=c-1
if(!(s>=0&&s<a.length))return A.b(a,s)
s=(a.charCodeAt(s)&64512)===55296}else s=!1
if(s)--c
for(s=k.c,r=s.$flags|0,q=s.length,p=a.length,o=b;o<c;++o){if(!(o<p))return A.b(a,o)
n=a.charCodeAt(o)
if(n<=127){m=k.b
if(m>=q)break
k.b=m+1
r&2&&A.K(s)
s[m]=n}else{m=n&64512
if(m===55296){if(k.b+4>q)break
m=o+1
if(!(m<p))return A.b(a,m)
if(k.bZ(n,a.charCodeAt(m)))o=m}else if(m===56320){if(k.b+3>q)break
k.ar()}else if(n<=2047){m=k.b
l=m+1
if(l>=q)break
k.b=l
r&2&&A.K(s)
if(!(m<q))return A.b(s,m)
s[m]=n>>>6|192
k.b=l+1
s[l]=n&63|128}else{m=k.b
if(m+2>=q)break
l=k.b=m+1
r&2&&A.K(s)
if(!(m<q))return A.b(s,m)
s[m]=n>>>12|224
m=k.b=l+1
if(!(l<q))return A.b(s,l)
s[l]=n>>>6&63|128
k.b=m+1
if(!(m<q))return A.b(s,m)
s[m]=n&63|128}}}return o}}
A.b1.prototype={
H(a,b){if(b==null)return!1
return b instanceof A.b1&&this.a===b.a},
gp(a){return B.a.gp(this.a)},
i(a){var s,r,q,p=this.a,o=p%36e8,n=B.a.D(o,6e7)
o%=6e7
s=n<10?"0":""
r=B.a.D(o,1e6)
q=r<10?"0":""
return""+(p/36e8|0)+":"+s+n+":"+q+r+"."+B.h.cd(B.a.i(o%1e6),6,"0")}}
A.eb.prototype={
i(a){return this.I()}}
A.n.prototype={
gP(){return A.iL(this)}}
A.cs.prototype={
i(a){var s=this.a
if(s!=null)return"Assertion failed: "+A.cB(s)
return"Assertion failed"}}
A.af.prototype={}
A.a2.prototype={
gaj(){return"Invalid argument"+(!this.a?"(s)":"")},
gai(){return""},
i(a){var s=this,r=s.c,q=r==null?"":" ("+r+")",p=s.d,o=p==null?"":": "+A.o(p),n=s.gaj()+q+o
if(!s.a)return n
return n+s.gai()+": "+A.cB(s.gaA())},
gaA(){return this.b}}
A.bR.prototype={
gaA(){return A.hA(this.b)},
gaj(){return"RangeError"},
gai(){var s,r=this.e,q=this.f
if(r==null)s=q!=null?": Not less than or equal to "+A.o(q):""
else if(q==null)s=": Not greater than or equal to "+A.o(r)
else if(q>r)s=": Not in inclusive range "+A.o(r)+".."+A.o(q)
else s=q<r?": Valid value range is empty":": Only valid value is "+A.o(r)
return s}}
A.cD.prototype={
gaA(){return A.u(this.b)},
gaj(){return"RangeError"},
gai(){if(A.u(this.b)<0)return": index must not be negative"
var s=this.f
if(s===0)return": no indices are valid"
return": index should be less than "+s},
gk(a){return this.f}}
A.bX.prototype={
i(a){return"Unsupported operation: "+this.a}}
A.cT.prototype={
i(a){return"UnimplementedError: "+this.a}}
A.ay.prototype={
i(a){return"Bad state: "+this.a}}
A.cz.prototype={
i(a){var s=this.a
if(s==null)return"Concurrent modification during iteration."
return"Concurrent modification during iteration: "+A.cB(s)+"."}}
A.cL.prototype={
i(a){return"Out of Memory"},
gP(){return null},
$in:1}
A.bT.prototype={
i(a){return"Stack Overflow"},
gP(){return null},
$in:1}
A.ec.prototype={
i(a){return"Exception: "+this.a}}
A.cC.prototype={
i(a){var s=this.a,r=""!==s?"FormatException: "+s:"FormatException"
return r}}
A.e.prototype={
gk(a){var s,r=this.gK(this)
for(s=0;r.n();)++s
return s},
i(a){return A.iu(this,"(",")")}}
A.r.prototype={
gp(a){return A.d.prototype.gp.call(this,0)},
i(a){return"null"}}
A.d.prototype={$id:1,
H(a,b){return this===b},
gp(a){return A.bQ(this)},
i(a){return"Instance of '"+A.cN(this)+"'"},
gl(a){return A.hU(this)},
toString(){return this.i(this)}}
A.d7.prototype={
i(a){return""},
$ia4:1}
A.bf.prototype={
gk(a){return this.a.length},
i(a){var s=this.a
return s.charCodeAt(0)==0?s:s},
$iiQ:1}
A.dH.prototype={
i(a){return"Promise was rejected with a value of `"+(this.a?"undefined":"null")+"`."}}
A.f7.prototype={
$1(a){return this.a.a7(this.b.h("0/?").a(a))},
$S:3}
A.f8.prototype={
$1(a){if(a==null)return this.a.be(new A.dH(a===undefined))
return this.a.be(a)},
$S:3}
A.e2.prototype={}
A.dk.prototype={
aX(){var s,r,q,p,o,n,m,l,k,j,i=this,h=null
for(s=i.c,r=i.b,q=r.length;;){p=i.e
if(p+7>s.byteLength)return h
o=!1
if(p+128===q){if(!(p>=0&&p<q))return A.b(r,p)
if(r[p]===84){n=p+1
if(!(n<q))return A.b(r,n)
if(r[n]===65){o=p+2
if(!(o<q))return A.b(r,o)
o=r[o]===71}}}if(o)return h
m=A.cp(r,p)
if(m>0&&i.e+m<=q){i.e+=m
continue}l=A.eP(s,i.e)
if(l!=null){r=i.e
q=l.a
if(r+q>s.byteLength)return h
i.w=q
return l}k=i.e
j=A.k3(s,k+1)
if(j<0)return h
i.e=j
p=i.f
o=i.w
i.f=p+(o>0?B.a.u(j-k+(o/2|0),o):0)}},
B(){var s=0,r=A.z(t.a),q,p=this,o,n,m,l,k,j,i,h
var $async$B=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:if(p.r)A.D(B.B)
o=p.aX()
if(o==null){q=null
s=1
break}n=p.e
m=o.d
l=o.a
k=l-m
j=new Uint8Array(k)
i=p.c
B.d.X(j,0,k,J.fd(B.i.gG(i),i.byteOffset+(n+m)))
n=p.d
m=n>0
h=m?B.a.u(p.f*1024*1e6,n):0
p.e+=l;++p.f
if(m)B.a.u(1024e6,n)
q=new A.at(j,h,h,!0,0)
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$B,r)},
v(a){var s=0,r=A.z(t.H),q=this,p,o,n
var $async$v=A.A(function(b,c){if(b===1)return A.w(c,r)
for(;;)switch(s){case 0:if(q.r)A.D(B.B)
q.e=A.fS(q.b)
q.f=0
p=q.d
o=p>0?B.a.D(B.a.D(a*p,1e6),1024):0
for(p=0;p<o;){n=q.aX()
if(n==null)break
p=q.f
if(p>=o)break
q.e=q.e+n.a;++p
q.f=p}return A.x(null,r)}})
return A.y($async$v,r)},
q(){var s=0,r=A.z(t.H),q,p=this
var $async$q=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:q=p.r=!0
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$q,r)},
gO(){return this.a}}
A.ew.prototype={}
A.bM.prototype={}
A.dC.prototype={
B(){var s=0,r=A.z(t.a),q,p=this,o,n,m,l,k,j
var $async$B=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:if(p.Q)A.D(B.x)
o=p.z
n=p.c
if(o>=n.length){q=null
s=1
break}m=n[o]
n=p.d
if(!(o<n.length)){q=A.b(n,o)
s=1
break}l=B.d.aI(p.b,m,m+n[o])
o=p.e
n=p.z
if(!(n<o.length)){q=A.b(o,n)
s=1
break}k=p.f
j=B.a.u(o[n]*1e6,k)
p.z=n+1
B.a.u(p.r*1e6,k)
q=new A.at(l,j,j,!0,0)
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$B,r)},
v(a){var s=0,r=A.z(t.H),q,p=this,o,n,m,l,k,j,i,h
var $async$v=A.A(function(b,c){if(b===1)return A.w(c,r)
for(;;)A:switch(s){case 0:if(p.Q)A.D(B.x)
o=a<=0?0:a
n=p.e
m=n.length
l=m-1
for(k=p.f,j=0,i=0;j<=l;){h=B.a.F(j+l,1)
if(!(h<m)){q=A.b(n,h)
s=1
break A}if(B.a.u(n[h]*1e6,k)<=o){j=h+1
i=h}else l=h-1}p.z=i
case 1:return A.x(q,r)}})
return A.y($async$v,r)},
q(){var s=0,r=A.z(t.H),q,p=this
var $async$q=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:q=p.Q=!0
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$q,r)},
gO(){return this.a}}
A.cZ.prototype={}
A.ak.prototype={}
A.dD.prototype={
B(){var s=0,r=A.z(t.a),q,p=this,o,n,m,l
var $async$B=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:if(p.e)A.D(B.y)
o=p.d
n=p.c
if(o>=n.length){q=null
s=1
break}p.d=o+1
m=n[o]
o=m.b
n=o+m.c
l=p.b
if(n>l.length){q=null
s=1
break}q=new A.at(new Uint8Array(A.bo(A.fn(l,o,n))),m.e,m.d,m.r,m.a)
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$B,r)},
v(a){var s=0,r=A.z(t.H),q,p=this,o,n,m,l,k,j,i,h,g,f,e
var $async$v=A.A(function(b,c){if(b===1)return A.w(c,r)
for(;;)A:switch(s){case 0:if(p.e)A.D(B.y)
o=p.a
n=B.b.c0(o,new A.dG())
for(m=p.c,l=m.length,k=o.length,j=0,i=-1,h=0;h<l;++h){g=m[h]
if(!g.r||g.e>a)continue
if(n){f=g.a
if(!(f<k)){q=A.b(o,f)
s=1
break A}f=!(o[f] instanceof A.bh)}else f=!1
if(f)continue
e=g.e
if(e>i){i=e
j=h}}p.d=j
case 1:return A.x(q,r)}})
return A.y($async$v,r)},
q(){var s=0,r=A.z(t.H),q,p=this
var $async$q=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:q=p.e=!0
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$q,r)},
gO(){return this.a}}
A.dF.prototype={
$2(a,b){var s=t.bf
return s.a(a).b-s.a(b).b},
$S:17}
A.dE.prototype={
$1(a){return B.a.u(a*1e6,this.a.a)},
$S:10}
A.dG.prototype={
$1(a){return t.ff.a(a) instanceof A.bh},
$S:18}
A.d_.prototype={}
A.eL.prototype={
$1(a){var s,r,q,p,o,n,m
for(s=this.b,r=s.length,q=this.a,p=0,o=0;o<a;++o){n=q.a
m=n>>>3
if(m>=r)return-1
p=(p<<1|B.a.bX(s[m],7-(n&7))&1)>>>0
q.a=n+1}return p},
$S:10}
A.ea.prototype={}
A.d1.prototype={}
A.dJ.prototype={
B(){var s=0,r=A.z(t.a),q,p=this,o,n,m,l
var $async$B=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:if(p.r)A.D(B.A)
o=p.f
n=p.b
if(o>=n.length){q=null
s=1
break}m=n[o]
n=p.c
if(!(o<n.length)){q=A.b(n,o)
s=1
break}l=B.a.D(n[o]*1e6,48e3)
n=p.d
if(!(o<n.length)){q=A.b(n,o)
s=1
break}B.a.D(n[o]*1e6,48e3)
p.f=o+1
q=new A.at(m,l,l,!0,0)
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$B,r)},
v(a){var s=0,r=A.z(t.H),q,p=this,o,n,m,l,k,j
var $async$v=A.A(function(b,c){if(b===1)return A.w(c,r)
for(;;)A:switch(s){case 0:if(p.r)A.D(B.A)
o=p.c
n=o.length
m=n-1
for(l=0,k=0;l<=m;){j=B.a.F(l+m,1)
if(!(j<n)){q=A.b(o,j)
s=1
break A}if(B.a.D(o[j]*1e6,48e3)<=a){l=j+1
k=j}else m=j-1}p.f=n===0?0:k
case 1:return A.x(q,r)}})
return A.y($async$v,r)},
q(){var s=0,r=A.z(t.H),q,p=this
var $async$q=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:q=p.r=!0
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$q,r)},
gO(){return this.a}}
A.bm.prototype={
I(){return"_Src."+this.b}}
A.dY.prototype={
B(){var s=0,r=A.z(t.a),q,p=this,o,n,m,l,k,j,i,h,g
var $async$B=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:if(p.x)A.D(B.z)
o=p.w
n=p.c
if(o>=n){q=null
s=1
break}m=p.f
l=p.e
k=4096*(A.co(m)*l)
j=n-o
if(j>k)j=k
j-=B.a.ac(j,A.co(m)*l)
if(j<=0){q=null
s=1
break}i=p.bH(p.b+o,j)
h=B.a.u(j,A.co(m)*l)
o=p.w
n=p.d
g=B.a.u(B.a.u(o,A.co(m)*l)*1e6,n)
p.w=o+j
B.a.u(h*1e6,n)
q=new A.at(i,g,g,!0,0)
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$B,r)},
bH(a,b){var s,r,q,p,o,n,m,l,k,j,i=this.a,h=J.dj(B.i.gG(i),i.byteOffset+a,b)
switch(this.f.a){case 1:case 3:return new Uint8Array(A.bo(h))
case 0:s=new Uint8Array(b*2)
r=A.ap(s,0,null)
for(i=h.length,q=r.$flags|0,p=0;p<b;++p){if(!(p<i))return A.b(h,p)
o=h[p]
q&2&&A.K(r,7)
r.setInt16(p*2,o-128<<8>>>0,!0)}return s
case 2:n=B.a.D(b,3)
s=new Uint8Array(n*4)
r=A.ap(s,0,null)
for(i=r.$flags|0,q=h.length,p=0;p<n;++p){o=p*3
if(!(o<q))return A.b(h,o)
m=h[o]
l=o+1
if(!(l<q))return A.b(h,l)
k=h[l]
o+=2
if(!(o<q))return A.b(h,o)
j=(m|k<<8|h[o]<<16)>>>0
if((j&8388608)!==0)j-=16777216
i&2&&A.K(r,12)
r.setFloat32(p*4,j/8388608,!0)}return s}},
v(a){var s=0,r=A.z(t.H),q=this,p,o,n
var $async$v=A.A(function(b,c){if(b===1)return A.w(c,r)
for(;;)switch(s){case 0:if(q.x)A.D(B.z)
p=q.f
o=q.e
n=B.a.c1(B.a.D(a*q.d,1e6)*(A.co(p)*o),0,q.c)
q.w=n-B.a.ac(n,A.co(p)*o)
return A.x(null,r)}})
return A.y($async$v,r)},
q(){var s=0,r=A.z(t.H),q,p=this
var $async$q=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:q=p.x=!0
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$q,r)},
gO(){return this.r}}
A.cV.prototype={
aq(){var s=this.d
this.d=null
if(s!=null&&(s.a.a&30)===0)s.bd()},
bL(a){var s,r,q,p,o,n,m,l
if(a==null||typeof a==="undefined")return
s=A.a_(a)
try{r=A.u(s.numberOfFrames)
q=A.u(s.numberOfChannels)
p=A.u(s.sampleRate)
o={planeIndex:0,format:"f32"}
n=A.u(s.allocationSize(o))
l=n
if(typeof l!=="number")return l.u()
l=B.l.D(l,4)
m=new Float32Array(l)
s.copyTo(m,o)
B.b.j(this.b,new A.b0(m,r,B.l.bn(A.fu(s.timestamp))))}finally{s.close()
this.aq()}},
a0(){var s=0,r=A.z(t.H),q,p=this,o
var $async$a0=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:if(p.b.length!==0||p.c!=null){s=1
break}o=new A.f($.h,t.D)
p.d=new A.ai(o,t.h)
s=3
return A.J(o.cj(B.at,new A.dZ()),$async$a0)
case 3:p.d=null
case 1:return A.x(q,r)}})
return A.y($async$a0,r)},
a5(){var s=this.c
if(s!=null){this.c=null
throw A.a(new A.ar("webcodecs",J.aY(s)))}},
a9(a){var s=0,r=A.z(t.W),q,p=this,o,n,m,l
var $async$a9=A.A(function(b,c){if(b===1)return A.w(c,r)
for(;;)switch(s){case 0:p.a5()
o=p.a
if(o==null)throw A.a(A.a9("WebCodecsAudioDecoder: not open"))
n=v.G.EncodedAudioChunk
m=a.e?"key":"delta"
o.decode(A.a_(new n({type:m,timestamp:a.b,data:a.a})))
s=3
return A.J(p.a0(),$async$a9)
case 3:p.a5()
m=p.b
l=A.fj(m,!0,t.R)
B.b.J(m)
q=l
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$a9,r)},
U(){var s=0,r=A.z(t.W),q,p=this,o,n,m
var $async$U=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:m=p.a
if(m==null){q=B.aF
s=1
break}s=3
return A.J(A.kK(A.a_(m.flush()),t.X),$async$U)
case 3:p.a5()
o=p.b
n=A.fj(o,!0,t.R)
B.b.J(o)
q=n
s=1
break
case 1:return A.x(q,r)}})
return A.y($async$U,r)},
q(){var s=0,r=A.z(t.H),q=this,p,o
var $async$q=A.A(function(a,b){if(a===1)return A.w(b,r)
for(;;)switch(s){case 0:try{p=q.a
if(p!=null)p.close()}catch(n){}q.a=null
B.b.J(q.b)
q.aq()
return A.x(null,r)}})
return A.y($async$q,r)}}
A.dZ.prototype={
$0(){},
$S:2}
A.e_.prototype={
$1(a){this.a.bL(a)},
$S:5}
A.e0.prototype={
$1(a){var s=this.a
s.c=a
s.aq()},
$S:5}
A.eV.prototype={
$1(a){var s=0,r=A.z(t.fn),q,p=this,o,n,m,l,k,j,i,h,g
var $async$$1=A.A(function(b,c){if(b===1)return A.w(c,r)
for(;;)switch(s){case 0:if("stats"===a){o=p.a
n=o.c
m=o.r
l=o.e
k=o.a
j=p.b
i=A.u(v.G.Atomics.load(j.b,5))
j=j.gbc()
o=o.f
q=A.fi(["framesWritten",n,"firstPtsUs",m,"seekGeneration",l,"eof",k,"underruns",i,"buffered",j,"error",o==null?null:J.aY(o)],t.N,t.X)
s=1
break}h=null
o=!1
if(t.j.b(a)){n=J.bv(a)
if(n.gk(a)===2)if("seek"===n.m(a,0)){g=n.m(a,1)
o=A.cl(g)
if(o){A.u(g)
h=g}}}if(o){p.a.d=h
q=null
s=1
break}if("stop"===a){p.a.b=!0
q=null
s=1
break}throw A.a(A.a9("unknown op: "+A.o(a)))
case 1:return A.x(q,r)}})
return A.y($async$$1,r)},
$S:19}
A.eW.prototype={
$0(){var s=this.a
return s.b||s.d!=null},
$S:20}
A.dL.prototype={
gbc(){var s=this.b,r=v.G
return B.a.aG(A.u(r.Atomics.load(s,0))-A.u(r.Atomics.load(s,1)),32)},
cm(a,b,c){var s,r,q,p,o,n,m,l,k,j,i,h=this.b
if(3>=h.length)return A.b(h,3)
s=h[3]
r=h[2]
if(b<=0)return 0
q=B.a.u(a.length,s)-c
if(q<=0)return 0
p=b>q?q:b
o=v.G
n=A.u(o.Atomics.load(h,0))
m=r-B.a.aG(n-A.u(o.Atomics.load(h,1)),32)
if(m<=0)return 0
if(p>m)p=m
l=B.a.ac(n,r)
k=l<0?l+r:l
j=r-k
if(p<=j)j=p
i=this.c
B.N.Y(i,k*s,(k+j)*s,a,c*s)
if(j<p)B.N.Y(i,0,(p-j)*s,a,(c+j)*s)
i=B.a.aG(n+p,32)
A.u(o.Atomics.store(h,0,i))
return p},
i(a){var s,r,q=this.b,p=q.length
if(2>=p)return A.b(q,2)
s=q[2]
if(3>=p)return A.b(q,3)
r=q[3]
if(4>=p)return A.b(q,4)
return"SharedAudioRing("+s+"f x "+r+"ch @ "+q[4]+"Hz, "+this.gbc()+" buffered, "+A.u(v.G.Atomics.load(q,5))+" underruns)"}}
A.bZ.prototype={
I(){return"VideoCodec."+this.b}}
A.ab.prototype={
I(){return"AudioCodec."+this.b}}
A.as.prototype={
I(){return"Container."+this.b}}
A.ae.prototype={}
A.bh.prototype={}
A.a7.prototype={}
A.dl.prototype={}
A.dB.prototype={
i(a){return A.hU(this).i(0)+": "+this.a}}
A.v.prototype={
i(a){return"CodecInitException["+this.b+"]: "+this.a}}
A.ar.prototype={
i(a){return"CodecRuntimeException["+this.b+"]: "+this.a}}
A.at.prototype={
i(a){var s=this,r=s.e?"KEY":"P/B"
return"EncodedPacket("+s.a.length+"B, pts="+s.b+"us, dts="+s.c+"us, "+r+", track="+s.f+")"}}
A.aD.prototype={}
A.b0.prototype={}
A.fa.prototype={
$1(a){var s,r,q,p,o,n=A.js(A.a_(a).data)
if(n==null)return
r=this.a
q=r.a
if(q!=null){q.c4(n)
return}s=null
try{s=A.fI(n.b,n.d)}catch(p){s=null}o=new A.d9(A.hc(t.B),new A.ai(new A.f($.h,t.D),t.h))
r.a=o
A.dg(o,this.b,s,B.a6).ci(new A.f9(),t.H)},
$S:21}
A.f9.prototype={
$1(a){A.a_(v.G.self).close()},
$S:22}
A.d9.prototype={
L(a){var s,r,q={},p=a.d,o=t.p.b(p),n=o?p.byteLength:0,m=new Uint8Array(12),l=A.ap(m,0,null)
l.$flags&2&&A.K(l,9)
l.setUint8(0,1)
l.setUint8(1,a.a.c)
l.setUint16(2,a.b,!0)
l.setUint32(4,a.c,!0)
l.setUint32(8,n,!0)
q.h=m
s=A.i([],t.f)
if(p!=null){p=o?p:A.fE(p,s)
q.p=p}r=A.kc(null,s)
A.a_(v.G.self).postMessage(q,r)},
c4(a){var s=this.a,r=s.b
if((r&4)!==0)return
s.j(0,a)},
$iiT:1}
A.eT.prototype={
$1(a){var s,r,q
for(s=this.a,r=s.length,q=0;q<r;++q)if(s[q]===a)return
B.b.j(s,a)
this.b[s.length-1]=a},
$S:23}
A.eS.prototype={
$2(a,b){this.a[A.o(a)]=A.fE(b,this.b)},
$S:1}
A.dN.prototype={
I(){return"SpawnHost."+this.b}}
A.dO.prototype={
I(){return"SpawnPayload."+this.b}}
A.dM.prototype={
bo(){return A.fi(["hosted","dart","payload","js","zeroCopyTransfer",!0],t.N,t.X)},
i(a){return"SpawnCaps(hosted: dart, payload: js, zeroCopyTransfer: true)"}}
A.cj.prototype={
c9(a){var s,r,q
t.k.a(a)
this.e=a
s=this.d
if(s.length===0)return
r=A.h1(s,t.B)
B.b.J(s)
for(s=r.length,q=0;q<r.length;r.length===s||(0,A.cq)(r),++q)this.aM(r[q],a)},
bO(a){var s,r,q=this
t.B.a(a)
switch(a.a.a){case 2:s=q.b
if((s.b&4)===0)s.j(0,A.fI(a.b,a.d))
break
case 3:r=q.e
if(r==null)B.b.j(q.d,a)
else q.aM(a,r)
break
case 1:q.am()
break
case 0:case 4:case 5:break}},
aM(a,b){var s,r,q,p,o,n,m,l,k=this,j={}
t.k.a(b)
j.a=null
try{j.a=A.fI(a.b,a.d)}catch(n){s=A.P(n)
r=A.S(n)
k.a3(a.c,s,r)
return}q=A.iZ()
try{m=q
j=A.ir(new A.eI(j,b),t.X)
l=m.b
if(l==null?m!=null:l!==m)A.D(new A.b5("Local '' has already been initialized."))
m.b=j}catch(n){p=A.P(n)
o=A.S(n)
k.a3(a.c,p,o)
return}j=q
m=j.b
if(m==null?j==null:m===j)A.D(new A.b5("Local '' has not been initialized."))
m.W(new A.eJ(k,a),new A.eK(k,a),t.P)},
a3(a,b,c){var s,r,q
t.l.a(c)
s=J.ao(b)
r=A.O(s.gl(b).a,null)
s=s.i(b)
q=c.i(0)
this.a.L(new A.U(B.j,0,a,B.k.a8(r+"\n"+A.fN(s,"\n"," ")+"\n"+q)))},
bQ(){return this.am()},
am(){var s,r=this
if(r.f)return
r.f=!0
s=r.c
if((s.a.a&30)===0)s.bd()
r.bI()
s=r.b
if((s.b&4)===0)s.q()},
bI(){var s,r,q,p,o,n,m,l=this.d
if(l.length===0)return
s=A.h1(l,t.B)
B.b.J(l)
for(l=s.length,r=this.a,q=0;q<s.length;s.length===l||(0,A.cq)(s),++q){p=s[q]
o=new A.ay("spawn: the worker closed without installing a request handler (WorkerChannel.handleRequests was never called)")
n=A.O(o.gl(0).a,null)
o=o.i(0)
m=B.f.i(0)
r.L(new A.U(B.j,0,p.c,B.k.a8(n+"\n"+A.fN(o,"\n"," ")+"\n"+m)))}},
$ifp:1}
A.eI.prototype={
$0(){return this.b.$1(this.a.a)},
$S:25}
A.eJ.prototype={
$1(a){var s,r,q,p,o,n,m=this
try{s=null
r=null
q=A.kt(a)
s=q.a
r=q.b
m.a.a.L(new A.U(B.P,s,m.b.c,r))}catch(n){p=A.P(n)
o=A.S(n)
m.a.a3(m.b.c,p,o)}},
$S:5}
A.eK.prototype={
$2(a,b){this.a.a3(this.b.c,A.a0(a),t.l.a(b))},
$S:4}
A.U.prototype={
i(a){var s=this,r=s.a.i(0),q=s.d
return"Frame("+r+", typeId: "+s.b+", correlationId: "+s.c+", payload: "+A.o(t.p.b(q)?""+q.byteLength+" bytes":J.bx(q))+")"}}
A.eO.prototype={
$2(a,b){if(typeof a!="string")throw A.a(A.aC(a,this.a,"spawn map keys must be String, got "+J.bx(a).i(0)))
A.fw(b,this.b,this.a+'["'+a+'"]')},
$S:1}
A.bd.prototype={
i(a){return"PlatformValue("+J.bx(this.a).i(0)+")"}}
A.ah.prototype={
I(){return"WireKind."+this.b}}
A.cW.prototype={
i(a){var s=this
return"WireHeader(v"+s.a+", "+s.b.i(0)+", typeId: "+s.c+", correlationId: "+s.d+", payloadLength: "+s.e+")"},
H(a,b){var s=this
if(b==null)return!1
return b instanceof A.cW&&b.a===s.a&&b.b===s.b&&b.c===s.c&&b.d===s.d&&b.e===s.e},
gp(a){var s=this
return A.h3(s.a,s.b,s.c,s.d,s.e)}}
A.e1.prototype={
c3(a,b){var s
this.a.m(0,a)
s=A.a9("spawn: no WireMessage decoder registered for typeId "+a+". Both ends must call the same WireRegistry.instance.register(...).")
throw A.a(s)}};(function aliases(){var s=J.av.prototype
s.bw=s.i
s=A.k.prototype
s.bx=s.Y})();(function installTearOffs(){var s=hunkHelpers._static_1,r=hunkHelpers._static_0,q=hunkHelpers._static_2,p=hunkHelpers._instance_2u,o=hunkHelpers._instance_1u,n=hunkHelpers._instance_0u
s(A,"kg","iV",6)
s(A,"kh","iW",6)
s(A,"ki","iX",6)
r(A,"hS","k9",0)
q(A,"kj","jS",9)
p(A.f.prototype,"gbC","bD",9)
s(A,"kq","jt",7)
s(A,"km","R",26)
var m
o(m=A.cj.prototype,"gbN","bO",24)
n(m,"gbP","bQ",0)})();(function inheritance(){var s=hunkHelpers.mixin,r=hunkHelpers.inherit,q=hunkHelpers.inheritMany
r(A.d,null)
q(A.d,[A.fg,J.cE,A.bS,J.bz,A.e9,A.n,A.k,A.aq,A.dK,A.e,A.bK,A.Q,A.aL,A.aQ,A.bB,A.dS,A.dI,A.bE,A.ca,A.bL,A.dy,A.aG,A.e8,A.d8,A.a3,A.d3,A.eE,A.eC,A.c_,A.E,A.G,A.c1,A.aj,A.f,A.cX,A.bU,A.cb,A.cY,A.c0,A.az,A.d0,A.a5,A.d6,A.ck,A.be,A.d4,A.c3,A.cy,A.cA,A.eu,A.eG,A.b1,A.eb,A.cL,A.bT,A.ec,A.cC,A.r,A.d7,A.bf,A.dH,A.e2,A.dk,A.ew,A.bM,A.dC,A.cZ,A.ak,A.dD,A.d_,A.ea,A.d1,A.dJ,A.dY,A.cV,A.dL,A.ae,A.dl,A.dB,A.at,A.aD,A.b0,A.d9,A.dM,A.cj,A.U,A.bd,A.cW,A.e1])
q(J.cE,[J.cG,J.bG,J.bI,J.b3,J.b4,J.bH,J.b2])
q(J.bI,[J.av,J.p,A.aw,A.bO])
q(J.av,[J.cM,J.bW,J.ac])
r(J.cF,A.bS)
r(J.dw,J.p)
q(J.bH,[J.bF,J.cH])
q(A.n,[A.b5,A.af,A.cI,A.cU,A.cP,A.d2,A.bJ,A.cs,A.a2,A.bX,A.cT,A.ay,A.cz])
r(A.bg,A.k)
r(A.cx,A.bg)
q(A.aq,[A.cv,A.cw,A.cS,A.f1,A.f3,A.e4,A.e3,A.eM,A.en,A.eq,A.dP,A.f7,A.f8,A.dE,A.dG,A.eL,A.e_,A.e0,A.eV,A.fa,A.f9,A.eT,A.eJ])
q(A.cv,[A.f6,A.e5,A.e6,A.eD,A.ds,A.ee,A.ej,A.ei,A.eg,A.ef,A.em,A.el,A.ek,A.ep,A.dQ,A.eB,A.eA,A.e7,A.ex,A.ez,A.eR,A.dZ,A.eW,A.eI])
q(A.e,[A.bD,A.bn])
r(A.bl,A.aQ)
r(A.c8,A.bl)
r(A.bC,A.bB)
r(A.bP,A.af)
q(A.cS,[A.cQ,A.aZ])
r(A.aF,A.bL)
r(A.dz,A.bD)
q(A.cw,[A.f2,A.eN,A.eU,A.eo,A.er,A.dA,A.ev,A.dF,A.eS,A.eK,A.eO])
r(A.b6,A.aw)
q(A.bO,[A.aI,A.H])
q(A.H,[A.c4,A.c6])
r(A.c5,A.c4)
r(A.bN,A.c5)
r(A.c7,A.c6)
r(A.W,A.c7)
q(A.bN,[A.aJ,A.b7])
q(A.W,[A.b8,A.b9,A.ba,A.bb,A.bc,A.aK,A.ax])
r(A.ce,A.d2)
r(A.ai,A.c1)
r(A.bi,A.cb)
r(A.cd,A.bU)
r(A.bj,A.cd)
r(A.bk,A.c0)
r(A.aM,A.az)
r(A.d5,A.ck)
r(A.c9,A.be)
r(A.c2,A.c9)
r(A.cK,A.bJ)
r(A.cJ,A.cy)
q(A.cA,[A.dx,A.dX])
r(A.et,A.eu)
q(A.a2,[A.bR,A.cD])
q(A.eb,[A.bm,A.bZ,A.ab,A.as,A.dN,A.dO,A.ah])
q(A.ae,[A.bh,A.a7])
q(A.dB,[A.v,A.ar])
s(A.bg,A.aL)
s(A.c4,A.k)
s(A.c5,A.Q)
s(A.c6,A.k)
s(A.c7,A.Q)
s(A.bi,A.cY)})()
var v={G:typeof self!="undefined"?self:globalThis,typeUniverse:{eC:new Map(),tR:{},eT:{},tPV:{},sEA:[]},mangledGlobalNames:{c:"int",m:"double",aX:"num",M:"String",an:"bool",r:"Null",j:"List",d:"Object",a8:"Map",q:"JSObject"},mangledNames:{},types:["~()","~(d?,d?)","r()","~(@)","r(d,a4)","r(d?)","~(~())","@(@)","r(@)","~(d,a4)","c(c)","L<~>()","@(@,M)","@(M)","r(~())","r(@,a4)","~(c,@)","c(ak,ak)","an(ae)","L<a8<M,d?>?>(d?)","an()","r(q)","r(~)","~(d)","~(U)","d?()","L<~>(fp)"],interceptorsByTag:null,leafTags:null,arrayRti:Symbol("$ti"),rttc:{"2;":(a,b)=>c=>c instanceof A.c8&&a.b(c.a)&&b.b(c.b)}}
A.je(v.typeUniverse,JSON.parse('{"ac":"av","cM":"av","bW":"av","kT":"aw","p":{"j":["1"],"q":[],"e":["1"]},"cG":{"an":[],"l":[]},"bG":{"r":[],"l":[]},"bI":{"q":[]},"av":{"q":[]},"cF":{"bS":[]},"dw":{"p":["1"],"j":["1"],"q":[],"e":["1"]},"bz":{"au":["1"]},"bH":{"m":[],"aX":[]},"bF":{"m":[],"c":[],"aX":[],"l":[]},"cH":{"m":[],"aX":[],"l":[]},"b2":{"M":[],"h4":[],"l":[]},"b5":{"n":[]},"cx":{"k":["c"],"aL":["c"],"j":["c"],"e":["c"],"k.E":"c","aL.E":"c"},"bD":{"e":["1"]},"bK":{"au":["1"]},"bg":{"k":["1"],"aL":["1"],"j":["1"],"e":["1"]},"c8":{"bl":[],"aQ":[]},"bB":{"a8":["1","2"]},"bC":{"bB":["1","2"],"a8":["1","2"]},"bP":{"af":[],"n":[]},"cI":{"n":[]},"cU":{"n":[]},"ca":{"a4":[]},"aq":{"aE":[]},"cv":{"aE":[]},"cw":{"aE":[]},"cS":{"aE":[]},"cQ":{"aE":[]},"aZ":{"aE":[]},"cP":{"n":[]},"aF":{"bL":["1","2"],"h_":["1","2"],"a8":["1","2"]},"dz":{"e":["1"]},"aG":{"au":["1"]},"bl":{"aQ":[]},"ax":{"W":[],"bV":[],"k":["c"],"H":["c"],"j":["c"],"V":["c"],"q":[],"t":[],"e":["c"],"Q":["c"],"l":[],"k.E":"c"},"aw":{"q":[],"bA":[],"l":[]},"b6":{"aw":[],"q":[],"bA":[],"l":[]},"bO":{"q":[],"t":[]},"d8":{"bA":[]},"aI":{"dm":[],"q":[],"t":[],"l":[]},"H":{"V":["1"],"q":[],"t":[]},"bN":{"k":["m"],"H":["m"],"j":["m"],"V":["m"],"q":[],"t":[],"e":["m"],"Q":["m"]},"W":{"k":["c"],"H":["c"],"j":["c"],"V":["c"],"q":[],"t":[],"e":["c"],"Q":["c"]},"aJ":{"dq":[],"k":["m"],"H":["m"],"j":["m"],"V":["m"],"q":[],"t":[],"e":["m"],"Q":["m"],"l":[],"k.E":"m"},"b7":{"dr":[],"k":["m"],"H":["m"],"j":["m"],"V":["m"],"q":[],"t":[],"e":["m"],"Q":["m"],"l":[],"k.E":"m"},"b8":{"W":[],"dt":[],"k":["c"],"H":["c"],"j":["c"],"V":["c"],"q":[],"t":[],"e":["c"],"Q":["c"],"l":[],"k.E":"c"},"b9":{"W":[],"du":[],"k":["c"],"H":["c"],"j":["c"],"V":["c"],"q":[],"t":[],"e":["c"],"Q":["c"],"l":[],"k.E":"c"},"ba":{"W":[],"dv":[],"k":["c"],"H":["c"],"j":["c"],"V":["c"],"q":[],"t":[],"e":["c"],"Q":["c"],"l":[],"k.E":"c"},"bb":{"W":[],"dU":[],"k":["c"],"H":["c"],"j":["c"],"V":["c"],"q":[],"t":[],"e":["c"],"Q":["c"],"l":[],"k.E":"c"},"bc":{"W":[],"dV":[],"k":["c"],"H":["c"],"j":["c"],"V":["c"],"q":[],"t":[],"e":["c"],"Q":["c"],"l":[],"k.E":"c"},"aK":{"W":[],"dW":[],"k":["c"],"H":["c"],"j":["c"],"V":["c"],"q":[],"t":[],"e":["c"],"Q":["c"],"l":[],"k.E":"c"},"d2":{"n":[]},"ce":{"af":[],"n":[]},"c_":{"dp":["1"]},"E":{"au":["1"]},"bn":{"e":["1"]},"G":{"n":[]},"c1":{"dp":["1"]},"ai":{"c1":["1"],"dp":["1"]},"f":{"L":["1"]},"cb":{"hb":["1"],"hq":["1"],"aN":["1"]},"bi":{"cY":["1"],"cb":["1"],"hb":["1"],"hq":["1"],"aN":["1"]},"bj":{"cd":["1"],"bU":["1"]},"bk":{"c0":["1"],"cR":["1"],"aN":["1"]},"c0":{"cR":["1"],"aN":["1"]},"cd":{"bU":["1"]},"aM":{"az":["1"]},"d0":{"az":["@"]},"ck":{"hi":[]},"d5":{"ck":[],"hi":[]},"c2":{"be":["1"],"e":["1"]},"c3":{"au":["1"]},"k":{"j":["1"],"e":["1"]},"bL":{"a8":["1","2"]},"be":{"e":["1"]},"c9":{"be":["1"],"e":["1"]},"bJ":{"n":[]},"cK":{"n":[]},"cJ":{"cy":["d?","M"]},"m":{"aX":[]},"c":{"aX":[]},"j":{"e":["1"]},"M":{"h4":[]},"cs":{"n":[]},"af":{"n":[]},"a2":{"n":[]},"bR":{"n":[]},"cD":{"n":[]},"bX":{"n":[]},"cT":{"n":[]},"ay":{"n":[]},"cz":{"n":[]},"cL":{"n":[]},"bT":{"n":[]},"d7":{"a4":[]},"bf":{"iQ":[]},"bh":{"ae":[]},"a7":{"ae":[]},"d9":{"iT":[]},"cj":{"fp":[]},"dm":{"t":[]},"dv":{"j":["c"],"t":[],"e":["c"]},"bV":{"j":["c"],"t":[],"e":["c"]},"dW":{"j":["c"],"t":[],"e":["c"]},"dt":{"j":["c"],"t":[],"e":["c"]},"dU":{"j":["c"],"t":[],"e":["c"]},"du":{"j":["c"],"t":[],"e":["c"]},"dV":{"j":["c"],"t":[],"e":["c"]},"dq":{"j":["m"],"t":[],"e":["m"]},"dr":{"j":["m"],"t":[],"e":["m"]}}'))
A.jd(v.typeUniverse,JSON.parse('{"bD":1,"bg":1,"H":1,"az":1,"c9":1,"cA":2}'))
var u={c:"Error handler must accept one Object or one Object and a StackTrace as arguments, and return a value of the returned future's type"}
var t=(function rtii(){var s=A.bu
return{r:s("@<~>"),n:s("G"),V:s("a7"),x:s("bA"),e:s("dm"),R:s("b0"),C:s("n"),w:s("dq"),gN:s("dr"),B:s("U"),Z:s("aE"),dQ:s("dt"),an:s("du"),U:s("dv"),bM:s("e<m>"),hf:s("e<@>"),hb:s("e<c>"),A:s("p<b0>"),b4:s("p<U>"),f:s("p<d>"),s:s("p<M>"),J:s("p<ae>"),eS:s("p<bV>"),fx:s("p<ak>"),b:s("p<@>"),t:s("p<c>"),c:s("p<d?>"),T:s("bG"),m:s("q"),g:s("ac"),aU:s("V<@>"),W:s("j<b0>"),j:s("j<@>"),bW:s("j<c>"),G:s("a8<@,@>"),eE:s("a8<M,d?>"),q:s("b6"),gT:s("aI"),E:s("aJ"),c2:s("b7"),at:s("b8"),ha:s("b9"),cv:s("ba"),eB:s("W"),dT:s("bb"),dk:s("bc"),gi:s("aK"),Y:s("ax"),P:s("r"),K:s("d"),u:s("bd"),fl:s("kU"),bQ:s("+()"),l:s("a4"),N:s("M"),ff:s("ae"),dm:s("l"),eK:s("af"),ak:s("t"),h7:s("dU"),bv:s("dV"),go:s("dW"),p:s("bV"),bI:s("bW"),g0:s("cV"),h:s("ai<~>"),_:s("f<@>"),fJ:s("f<c>"),D:s("f<~>"),bf:s("ak"),fv:s("cc<d?>"),g6:s("bn<cZ>"),y:s("an"),al:s("an(d)"),i:s("m"),z:s("@"),O:s("@()"),v:s("@(d)"),Q:s("@(d,a4)"),S:s("c"),a:s("at?"),eH:s("L<r>?"),bX:s("q?"),fn:s("a8<M,d?>?"),dE:s("ax?"),X:s("d?"),k:s("d?(d?)"),c8:s("M?"),ev:s("az<@>?"),F:s("aj<@,@>?"),L:s("d4?"),fQ:s("an?"),I:s("m?"),h6:s("c?"),cg:s("aX?"),d:s("~()?"),o:s("aX"),H:s("~"),M:s("~()"),d5:s("~(d)"),da:s("~(d,a4)")}})();(function constants(){var s=hunkHelpers.makeConstList
B.av=J.cE.prototype
B.b=J.p.prototype
B.a=J.bF.prototype
B.l=J.bH.prototype
B.h=J.b2.prototype
B.aw=J.ac.prototype
B.ax=J.bI.prototype
B.i=A.aI.prototype
B.N=A.aJ.prototype
B.d=A.ax.prototype
B.O=J.cM.prototype
B.p=J.bW.prototype
B.m=new A.ab(0,"aac")
B.n=new A.ab(1,"opus")
B.V=new A.ab(2,"vorbis")
B.t=new A.ab(3,"mp3")
B.W=new A.ab(4,"flac")
B.X=new A.ab(5,"pcmS16le")
B.Y=new A.ab(6,"pcmF32le")
B.u=function getTagFallback(o) {
  var s = Object.prototype.toString.call(o);
  return s.substring(8, s.length - 1);
}
B.Z=function() {
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
B.a3=function(getTagFallback) {
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
B.a_=function(hooks) {
  if (typeof dartExperimentalFixupGetTag != "function") return hooks;
  hooks.getTag = dartExperimentalFixupGetTag(hooks.getTag);
}
B.a2=function(hooks) {
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
B.a1=function(hooks) {
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
B.a0=function(hooks) {
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
B.v=function(hooks) { return hooks; }

B.a4=new A.cJ()
B.a5=new A.cL()
B.e=new A.dK()
B.b2=new A.dN(0,"dart")
B.b3=new A.dO(1,"js")
B.a6=new A.dM()
B.k=new A.dX()
B.w=new A.d0()
B.c=new A.d5()
B.f=new A.d7()
B.a7=new A.v("ogg","first packet is not OpusHead")
B.a8=new A.v("wav","EXTENSIBLE SubFormat is not a PCM/IEEE-float GUID")
B.a9=new A.v("ogg","not an Ogg stream")
B.aa=new A.v("mp4","no stbl samples (fragmented MP4?) \u2014 deferring to fallback")
B.ab=new A.v("adts","bad ADTS sample-rate/channels")
B.ac=new A.v("mp4","no tracks in moov")
B.ad=new A.v("mp3","free-format MP3 (bitrate index 0) is not supported \u2014 its frame length is not derivable from the header")
B.ae=new A.v("mp3","no MPEG Layer III audio frames")
B.af=new A.v("wav","short WAVE_FORMAT_EXTENSIBLE")
B.ag=new A.v("wav","missing data chunk")
B.ah=new A.v("adts","no ADTS sync")
B.ai=new A.v("ogg","truncated segment table")
B.aj=new A.v("mp4","no moov box")
B.ak=new A.v("audio-worker","container has no audio track")
B.al=new A.v("wav","missing/short fmt chunk")
B.am=new A.v("audio-worker","no pure-Dart parser claims this container")
B.an=new A.v("ogg","bad page capture pattern")
B.ao=new A.v("wav","not a RIFF/WAVE file")
B.ap=new A.v("ogg","truncated page payload")
B.aq=new A.v("mp3","no MPEG Layer III frame sync")
B.x=new A.ar("mp3","demuxer closed")
B.y=new A.ar("mp4","demuxer closed")
B.z=new A.ar("wav","demuxer closed")
B.A=new A.ar("ogg","demuxer closed")
B.B=new A.ar("adts","demuxer closed")
B.C=new A.as(0,"mp4")
B.D=new A.as(10,"adts")
B.E=new A.as(6,"ogg")
B.F=new A.as(7,"wav")
B.ar=new A.as(8,"m4a")
B.o=new A.as(9,"mp3")
B.as=new A.b1(0)
B.G=new A.b1(1e4)
B.at=new A.b1(2e4)
B.r=new A.ah(1,1,"bye")
B.au=new A.U(B.r,0,0,null)
B.ay=new A.dx(null)
B.q=new A.ah(0,0,"hello")
B.b0=new A.ah(2,2,"message")
B.b1=new A.ah(3,3,"request")
B.P=new A.ah(4,4,"response")
B.j=new A.ah(5,5,"error")
B.az=s([B.q,B.r,B.b0,B.b1,B.P,B.j],A.bu("p<ah>"))
B.H=s([11025,12e3,8000],t.t)
B.I=s([22050,24e3,16e3],t.t)
B.J=s([44100,48e3,32e3],t.t)
B.aA=s([79,103,103,83],t.t)
B.aB=s([0,8,16,24,32,40,48,56,64,80,96,112,128,144,160,0],t.t)
B.aC=s([480,960,1920,2880,480,960,1920,2880,480,960,1920,2880,480,960,480,960,120,240,480,960,120,240,480,960,120,240,480,960,120,240,480,960],t.t)
B.K=s([79,112,117,115,72,101,97,100],t.t)
B.aD=s(["Xing","Info"],t.s)
B.aE=s([0,0,0,0,16,0,128,0,0,170,0,56,155,113],t.t)
B.L=s([96e3,88200,64e3,48e3,44100,32e3,24e3,22050,16e3,12e3,11025,8000,7350,0,0,0],t.t)
B.aF=s([],t.A)
B.M=s([],t.t)
B.aG=s([0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0],t.t)
B.aH=s([79,112,117,115,84,97,103,115],t.t)
B.aI=s([96e3,88200,64e3,48e3,44100,32e3,24e3,22050,16e3,12e3,11025,8000,7350],t.t)
B.aK={}
B.aJ=new A.bC(B.aK,[],A.bu("bC<M,M>"))
B.aL=A.a1("bA")
B.aM=A.a1("dm")
B.aN=A.a1("dq")
B.aO=A.a1("dr")
B.aP=A.a1("dt")
B.aQ=A.a1("du")
B.aR=A.a1("dv")
B.aS=A.a1("q")
B.aT=A.a1("d")
B.aU=A.a1("dU")
B.aV=A.a1("dV")
B.aW=A.a1("dW")
B.aX=A.a1("bV")
B.aY=new A.bZ(0,"h264")
B.aZ=new A.bZ(1,"hevc")
B.b_=new A.bZ(2,"av1")
B.Q=new A.d1(0,0)
B.R=new A.bm(0,"u8")
B.S=new A.bm(1,"s16")
B.T=new A.bm(2,"s24")
B.U=new A.bm(3,"f32")})();(function staticFields(){$.es=null
$.Y=A.i([],t.f)
$.h6=null
$.fV=null
$.fU=null
$.hV=null
$.hR=null
$.hY=null
$.eY=null
$.f4=null
$.fJ=null
$.ey=A.i([],A.bu("p<j<d>?>"))
$.bp=null
$.cm=null
$.cn=null
$.fA=!1
$.h=B.c})();(function lazyInitializers(){var s=hunkHelpers.lazyFinal
s($,"kR","fO",()=>A.kx("_$dart_dartClosure"))
s($,"l8","fc",()=>A.iI(0))
s($,"lc","ic",()=>B.c.aE(new A.f6(),A.bu("L<~>")))
s($,"la","ib",()=>A.i([new J.cF()],A.bu("p<bS>")))
s($,"kW","i0",()=>A.ag(A.dT({
toString:function(){return"$receiver$"}})))
s($,"kX","i1",()=>A.ag(A.dT({$method$:null,
toString:function(){return"$receiver$"}})))
s($,"kY","i2",()=>A.ag(A.dT(null)))
s($,"kZ","i3",()=>A.ag(function(){var $argumentsExpr$="$arguments$"
try{null.$method$($argumentsExpr$)}catch(r){return r.message}}()))
s($,"l1","i6",()=>A.ag(A.dT(void 0)))
s($,"l2","i7",()=>A.ag(function(){var $argumentsExpr$="$arguments$"
try{(void 0).$method$($argumentsExpr$)}catch(r){return r.message}}()))
s($,"l0","i5",()=>A.ag(A.hg(null)))
s($,"l_","i4",()=>A.ag(function(){try{null.$method$}catch(r){return r.message}}()))
s($,"l4","i9",()=>A.ag(A.hg(void 0)))
s($,"l3","i8",()=>A.ag(function(){try{(void 0).$method$}catch(r){return r.message}}()))
s($,"l7","fP",()=>A.iU())
s($,"kS","fb",()=>$.ic())
s($,"l9","dh",()=>A.hW(B.aT))
s($,"l6","ia",()=>new A.e1(A.h0(t.S,A.bu("l5(bV)"))))})();(function nativeSupport(){!function(){var s=function(a){var m={}
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
hunkHelpers.setOrUpdateInterceptorsByTag({SharedArrayBuffer:A.aw,ArrayBuffer:A.b6,ArrayBufferView:A.bO,DataView:A.aI,Float32Array:A.aJ,Float64Array:A.b7,Int16Array:A.b8,Int32Array:A.b9,Int8Array:A.ba,Uint16Array:A.bb,Uint32Array:A.bc,Uint8ClampedArray:A.aK,CanvasPixelArray:A.aK,Uint8Array:A.ax})
hunkHelpers.setOrUpdateLeafTags({SharedArrayBuffer:true,ArrayBuffer:true,ArrayBufferView:false,DataView:true,Float32Array:true,Float64Array:true,Int16Array:true,Int32Array:true,Int8Array:true,Uint16Array:true,Uint32Array:true,Uint8ClampedArray:true,CanvasPixelArray:true,Uint8Array:false})
A.H.$nativeSuperclassTag="ArrayBufferView"
A.c4.$nativeSuperclassTag="ArrayBufferView"
A.c5.$nativeSuperclassTag="ArrayBufferView"
A.bN.$nativeSuperclassTag="ArrayBufferView"
A.c6.$nativeSuperclassTag="ArrayBufferView"
A.c7.$nativeSuperclassTag="ArrayBufferView"
A.W.$nativeSuperclassTag="ArrayBufferView"})()
Function.prototype.$1=function(a){return this(a)}
Function.prototype.$2=function(a,b){return this(a,b)}
Function.prototype.$0=function(){return this()}
Function.prototype.$3=function(a,b,c){return this(a,b,c)}
Function.prototype.$4=function(a,b,c,d){return this(a,b,c,d)}
Function.prototype.$1$1=function(a){return this(a)}
convertAllToFastObject(w)
convertToFastObject($);(function(a){if(typeof document==="undefined"){a(null)
return}if(typeof document.currentScript!="undefined"){a(document.currentScript)
return}var s=document.scripts
function onLoad(b){for(var q=0;q<s.length;++q){s[q].removeEventListener("load",onLoad,false)}a(b.target)}for(var r=0;r<s.length;++r){s[r].addEventListener("load",onLoad,false)}})(function(a){v.currentScript=a
var s=A.kG
if(typeof dartMainRunner==="function"){dartMainRunner(s,[])}else{s([])}})})()
//# sourceMappingURL=audio_playback_worker.dart.js.map
