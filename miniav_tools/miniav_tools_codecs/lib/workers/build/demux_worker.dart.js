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
return q}}function makeConstList(a,b){if(b!=null)A.f(a,b)
a.$flags=7
return a}function convertToFastObject(a){function t(){}t.prototype=a
new t()
return a}function convertAllToFastObject(a){for(var s=0;s<a.length;++s){convertToFastObject(a[s])}}var y=0
function instanceTearOffGetter(a,b){var s=null
return a?function(c){if(s===null)s=A.fB(b)
return new s(c,this)}:function(){if(s===null)s=A.fB(b)
return new s(this,null)}}function staticTearOffGetter(a){var s=null
return function(){if(s===null)s=A.fB(a).prototype
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
fJ(a,b,c,d){return{i:a,p:b,e:c,x:d}},
f1(a){var s,r,q,p,o,n="_$dart_js",m=a[v.dispatchPropertyName]
if(m==null)if($.fG==null){A.kB()
m=a[v.dispatchPropertyName]}if(m!=null){s=m.p
if(!1===s)return m.i
if(!0===s)return a
r=Object.getPrototypeOf(a)
if(s===r)return m.i
if(m.e===r)throw A.b(A.hc("Return interceptor for "+A.p(s(a,m))))}q=a.constructor
if(q==null)p=null
else{o=$.eq
if(o==null)o=$.eq=A.f0(n)
p=q[o]}if(p!=null)return p
p=A.kF(a)
if(p!=null)return p
if(typeof a=="function")return B.aC
s=Object.getPrototypeOf(a)
if(s==null)return B.R
if(s===Object.prototype)return B.R
if(typeof q=="function"){o=$.eq
if(o==null)o=$.eq=A.f0(n)
Object.defineProperty(q,o,{value:B.r,enumerable:false,writable:true,configurable:true})
return B.r}return B.r},
iu(a,b){if(a<0||a>4294967295)throw A.b(A.a4(a,0,4294967295,"length",null))
return J.iv(new Array(a),b)},
iv(a,b){var s=A.f(a,b.h("o<0>"))
s.$flags=1
return s},
at(a){if(typeof a=="number"){if(Math.floor(a)==a)return J.bI.prototype
return J.cM.prototype}if(typeof a=="string")return J.b7.prototype
if(a==null)return J.bJ.prototype
if(typeof a=="boolean")return J.cL.prototype
if(Array.isArray(a))return J.o.prototype
if(typeof a!="object"){if(typeof a=="function")return J.ai.prototype
if(typeof a=="symbol")return J.b9.prototype
if(typeof a=="bigint")return J.b8.prototype
return a}if(a instanceof A.d)return a
return J.f1(a)},
cr(a){if(typeof a=="string")return J.b7.prototype
if(a==null)return a
if(Array.isArray(a))return J.o.prototype
if(typeof a!="object"){if(typeof a=="function")return J.ai.prototype
if(typeof a=="symbol")return J.b9.prototype
if(typeof a=="bigint")return J.b8.prototype
return a}if(a instanceof A.d)return a
return J.f1(a)},
dr(a){if(a==null)return a
if(Array.isArray(a))return J.o.prototype
if(typeof a!="object"){if(typeof a=="function")return J.ai.prototype
if(typeof a=="symbol")return J.b9.prototype
if(typeof a=="bigint")return J.b8.prototype
return a}if(a instanceof A.d)return a
return J.f1(a)},
fE(a){if(a==null)return a
if(typeof a!="object"){if(typeof a=="function")return J.ai.prototype
if(typeof a=="symbol")return J.b9.prototype
if(typeof a=="bigint")return J.b8.prototype
return a}if(a instanceof A.d)return a
return J.f1(a)},
ct(a,b){if(a==null)return b==null
if(typeof a!="object")return b!=null&&a===b
return J.at(a).K(a,b)},
ib(a,b,c){return J.fE(a).bj(a,b,c)},
fb(a,b){return J.fE(a).bk(a,b)},
cu(a,b,c){return J.fE(a).aj(a,b,c)},
ic(a,b){return J.dr(a).X(a,b)},
Q(a){return J.at(a).gp(a)},
fc(a){return J.dr(a).gE(a)},
cv(a){return J.cr(a).gk(a)},
bz(a){return J.at(a).gl(a)},
id(a,b){return J.dr(a).ap(a,b)},
ie(a,b){return J.dr(a).bx(a,b)},
cw(a){return J.at(a).i(a)},
cJ:function cJ(){},
cL:function cL(){},
bJ:function bJ(){},
bL:function bL(){},
ax:function ax(){},
cQ:function cQ(){},
c1:function c1(){},
ai:function ai(){},
b8:function b8(){},
b9:function b9(){},
o:function o(a){this.$ti=a},
cK:function cK(){},
dE:function dE(a){this.$ti=a},
bA:function bA(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
bK:function bK(){},
bI:function bI(){},
cM:function cM(){},
b7:function b7(){}},A={fh:function fh(){},
fV(a){return new A.ba("Field '"+a+"' has been assigned during initialization.")},
W(a,b){a=a+b&536870911
a=a+((a&524287)<<10)&536870911
return a^a>>>6},
dV(a){a=a+((a&67108863)<<3)&536870911
a^=a>>>11
return a+((a&16383)<<15)&536870911},
dn(a,b,c){return a},
fI(a){var s,r
for(s=$.Y.length,r=0;r<s;++r)if(a===$.Y[r])return!0
return!1},
cX(a,b,c,d){A.bW(b,"start")
if(c!=null){A.bW(c,"end")
if(b>c)A.n(A.a4(b,0,c,"start",null))}return new A.c0(a,b,c,d.h("c0<0>"))},
fT(){return new A.aA("No element")},
d7:function d7(a){this.a=0
this.b=a},
d5:function d5(a){this.a=0
this.b=a},
ba:function ba(a){this.a=a},
cC:function cC(a){this.a=a},
f7:function f7(){},
dR:function dR(){},
bD:function bD(){},
aK:function aK(){},
c0:function c0(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.$ti=d},
aL:function aL(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
bE:function bE(a){this.$ti=a},
bF:function bF(a){this.$ti=a},
O:function O(){},
aS:function aS(){},
bk:function bk(){},
hV(a){var s=A.hU(a)
if(s!=null)return s
return"minified:"+a},
lg(a,b){var s
if(b!=null){s=b.x
if(s!=null)return s}return t.aU.b(a)},
p(a){var s
if(typeof a=="string")return a
if(typeof a=="number"){if(a!==0)return""+a}else if(!0===a)return"true"
else if(!1===a)return"false"
else if(a==null)return"null"
s=J.cw(a)
return s},
bU(a){var s,r=$.h4
if(r==null)r=$.h4=Symbol("identityHashCode")
s=a[r]
if(s==null){s=Math.random()*0x3fffffff|0
a[r]=s}return s},
cR(a){var s,r,q,p
if(a instanceof A.d)return A.M(A.au(a),null)
s=J.at(a)
if(s===B.aB||s===B.aD||t.bI.b(a)){r=B.y(a)
if(r!=="Object"&&r!=="")return r
q=a.constructor
if(typeof q=="function"){p=q.name
if(typeof p=="string"&&p!=="Object"&&p!=="")return p}}return A.M(A.au(a),null)},
h5(a){var s,r,q
if(a==null||typeof a=="number"||A.dk(a))return J.cw(a)
if(typeof a=="string")return JSON.stringify(a)
if(a instanceof A.aw)return a.i(0)
if(a instanceof A.aY)return a.bi(!0)
s=$.i9()
for(r=0;r<1;++r){q=s[r].cD(a)
if(q!=null)return q}return"Instance of '"+A.cR(a)+"'"},
h3(a){var s,r,q,p,o=a.length
if(o<=500)return String.fromCharCode.apply(null,a)
for(s="",r=0;r<o;r=q){q=r+500
p=q<o?q:o
s+=String.fromCharCode.apply(null,a.slice(r,p))}return s},
iJ(a){var s,r,q,p=A.f([],t.t)
for(s=a.length,r=0;r<a.length;a.length===s||(0,A.b5)(a),++r){q=a[r]
if(!A.co(q))throw A.b(A.bw(q))
if(q<=65535)B.a.j(p,q)
else if(q<=1114111){B.a.j(p,55296+(B.b.H(q-65536,10)&1023))
B.a.j(p,56320+(q&1023))}else throw A.b(A.bw(q))}return A.h3(p)},
h6(a){var s,r,q
for(s=a.length,r=0;r<s;++r){q=a[r]
if(!A.co(q))throw A.b(A.bw(q))
if(q<0)throw A.b(A.bw(q))
if(q>65535)return A.iJ(a)}return A.h3(a)},
iK(a,b,c){var s,r,q,p
if(c<=500&&b===0&&c===a.length)return String.fromCharCode.apply(null,a)
for(s=b,r="";s<c;s=q){q=s+500
p=q<c?q:c
r+=String.fromCharCode.apply(null,a.subarray(s,p))}return r},
v(a){var s
if(a<=65535)return String.fromCharCode(a)
if(a<=1114111){s=a-65536
return String.fromCharCode((B.b.H(s,10)|55296)>>>0,s&1023|56320)}throw A.b(A.a4(a,0,1114111,null,null))},
iI(a){var s=a.$thrownJsError
if(s==null)return null
return A.S(s)},
iL(a,b){var s
if(a.$thrownJsError==null){s=new Error()
A.y(a,s)
a.$thrownJsError=s
s.stack=b.i(0)}},
hP(a){throw A.b(A.bw(a))},
a(a,b){if(a==null)J.cv(a)
throw A.b(A.eZ(a,b))},
eZ(a,b){var s,r="index"
if(!A.co(b))return new A.a1(!0,b,r,null)
s=A.aa(J.cv(a))
if(b<0||b>=s)return A.ff(b,s,a,r)
return new A.bV(null,null,!0,b,r,"Value not in range")},
ku(a,b,c){if(a>c)return A.a4(a,0,c,"start",null)
if(b!=null)if(b<a||b>c)return A.a4(b,a,c,"end",null)
return new A.a1(!0,b,"end",null)},
bw(a){return new A.a1(!0,a,null,null)},
b(a){return A.y(a,new Error())},
y(a,b){var s
if(a==null)a=new A.ak()
b.dartException=a
s=A.kR
if("defineProperty" in Object){Object.defineProperty(b,"message",{get:s})
b.name=""}else b.toString=s
return b},
kR(){return J.cw(this.dartException)},
n(a,b){throw A.y(a,b==null?new Error():b)},
z(a,b,c){var s
if(b==null)b=0
if(c==null)c=0
s=Error()
A.n(A.jx(a,b,c),s)},
jx(a,b,c){var s,r,q,p,o,n,m,l,k
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
return new A.c2("'"+s+"': Cannot "+o+" "+l+k+n)},
b5(a){throw A.b(A.bC(a))},
al(a){var s,r,q,p,o,n
a=A.hT(a.replace(String({}),"$receiver$"))
s=a.match(/\\\$[a-zA-Z]+\\\$/g)
if(s==null)s=A.f([],t.s)
r=s.indexOf("\\$arguments\\$")
q=s.indexOf("\\$argumentsExpr\\$")
p=s.indexOf("\\$expr\\$")
o=s.indexOf("\\$method\\$")
n=s.indexOf("\\$receiver\\$")
return new A.dW(a.replace(new RegExp("\\\\\\$arguments\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$argumentsExpr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$expr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$method\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$receiver\\\\\\$","g"),"((?:x|[^x])*)"),r,q,p,o,n)},
dX(a){return function($expr$){var $argumentsExpr$="$arguments$"
try{$expr$.$method$($argumentsExpr$)}catch(s){return s.message}}(a)},
hb(a){return function($expr$){try{$expr$.$method$}catch(s){return s.message}}(a)},
fi(a,b){var s=b==null,r=s?null:b.method
return new A.cN(a,r,s?null:b.receiver)},
P(a){var s
if(a==null)return new A.dP(a)
if(a instanceof A.bG){s=a.a
return A.aF(a,s==null?A.ap(s):s)}if(typeof a!=="object")return a
if("dartException" in a)return A.aF(a,a.dartException)
return A.kh(a)},
aF(a,b){if(t.Q.b(b))if(b.$thrownJsError==null)b.$thrownJsError=a
return b},
kh(a){var s,r,q,p,o,n,m,l,k,j,i,h,g
if(!("message" in a))return a
s=a.message
if("number" in a&&typeof a.number=="number"){r=a.number
q=r&65535
if((B.b.H(r,16)&8191)===10)switch(q){case 438:return A.aF(a,A.fi(A.p(s)+" (Error "+q+")",null))
case 445:case 5007:A.p(s)
return A.aF(a,new A.bS())}}if(a instanceof TypeError){p=$.hX()
o=$.hY()
n=$.hZ()
m=$.i_()
l=$.i2()
k=$.i3()
j=$.i1()
$.i0()
i=$.i5()
h=$.i4()
g=p.G(s)
if(g!=null)return A.aF(a,A.fi(A.aq(s),g))
else{g=o.G(s)
if(g!=null){g.method="call"
return A.aF(a,A.fi(A.aq(s),g))}else if(n.G(s)!=null||m.G(s)!=null||l.G(s)!=null||k.G(s)!=null||j.G(s)!=null||m.G(s)!=null||i.G(s)!=null||h.G(s)!=null){A.aq(s)
return A.aF(a,new A.bS())}}return A.aF(a,new A.d0(typeof s=="string"?s:""))}if(a instanceof RangeError){if(typeof s=="string"&&s.indexOf("call stack")!==-1)return new A.bZ()
s=function(b){try{return String(b)}catch(f){}return null}(a)
return A.aF(a,new A.a1(!1,null,null,typeof s=="string"?s.replace(/^RangeError:\s*/,""):s))}if(typeof InternalError=="function"&&a instanceof InternalError)if(typeof s=="string"&&s==="too much recursion")return new A.bZ()
return a},
S(a){var s
if(a instanceof A.bG)return a.b
if(a==null)return new A.cd(a)
s=a.$cachedTrace
if(s!=null)return s
s=new A.cd(a)
if(typeof a==="object")a.$cachedTrace=s
return s},
hQ(a){if(a==null)return J.Q(a)
if(typeof a=="object")return A.bU(a)
return J.Q(a)},
ky(a,b){var s,r,q,p=a.length
for(s=0;s<p;s=q){r=s+1
q=r+1
b.q(0,a[s],a[r])}return b},
jG(a,b,c,d,e,f){t.Z.a(a)
switch(A.aa(b)){case 0:return a.$0()
case 1:return a.$1(c)
case 2:return a.$2(c,d)
case 3:return a.$3(c,d,e)
case 4:return a.$4(c,d,e,f)}throw A.b(new A.ef("Unsupported number of arguments for wrapped closure"))},
dp(a,b){var s=a.$identity
if(!!s)return s
s=A.kn(a,b)
a.$identity=s
return s},
kn(a,b){var s
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
return function(c,d,e){return function(f,g,h,i){return e(c,d,f,g,h,i)}}(a,b,A.jG)},
im(a2){var s,r,q,p,o,n,m,l,k,j,i=a2.co,h=a2.iS,g=a2.iI,f=a2.nDA,e=a2.aI,d=a2.fs,c=a2.cs,b=d[0],a=c[0],a0=i[b],a1=a2.fT
a1.toString
s=h?Object.create(new A.cV().constructor.prototype):Object.create(new A.b6(null,null).constructor.prototype)
s.$initialize=s.constructor
r=h?function static_tear_off(){this.$initialize()}:function tear_off(a3,a4){this.$initialize(a3,a4)}
s.constructor=r
r.prototype=s
s.$_name=b
s.$_target=a0
q=!h
if(q)p=A.fS(b,a0,g,f)
else{s.$static_name=b
p=a0}s.$S=A.ii(a1,h,g)
s[a]=p
for(o=p,n=1;n<d.length;++n){m=d[n]
if(typeof m=="string"){l=i[m]
k=m
m=l}else k=""
j=c[n]
if(j!=null){if(q)m=A.fS(k,m,g,f)
s[j]=m}if(n===e)o=m}s.$C=o
s.$R=a2.rC
s.$D=a2.dV
return r},
ii(a,b,c){if(typeof a=="number")return a
if(typeof a=="string"){if(b)throw A.b("Cannot compute signature for static tearoff.")
return function(d,e){return function(){return e(this,d)}}(a,A.ig)}throw A.b("Error in functionType of tearoff")},
ij(a,b,c,d){var s=A.fR
switch(b?-1:a){case 0:return function(e,f){return function(){return f(this)[e]()}}(c,s)
case 1:return function(e,f){return function(g){return f(this)[e](g)}}(c,s)
case 2:return function(e,f){return function(g,h){return f(this)[e](g,h)}}(c,s)
case 3:return function(e,f){return function(g,h,i){return f(this)[e](g,h,i)}}(c,s)
case 4:return function(e,f){return function(g,h,i,j){return f(this)[e](g,h,i,j)}}(c,s)
case 5:return function(e,f){return function(g,h,i,j,k){return f(this)[e](g,h,i,j,k)}}(c,s)
default:return function(e,f){return function(){return e.apply(f(this),arguments)}}(d,s)}},
fS(a,b,c,d){if(c)return A.il(a,b,d)
return A.ij(b.length,d,a,b)},
ik(a,b,c,d){var s=A.fR,r=A.ih
switch(b?-1:a){case 0:throw A.b(new A.cS("Intercepted function with no arguments."))
case 1:return function(e,f,g){return function(){return f(this)[e](g(this))}}(c,r,s)
case 2:return function(e,f,g){return function(h){return f(this)[e](g(this),h)}}(c,r,s)
case 3:return function(e,f,g){return function(h,i){return f(this)[e](g(this),h,i)}}(c,r,s)
case 4:return function(e,f,g){return function(h,i,j){return f(this)[e](g(this),h,i,j)}}(c,r,s)
case 5:return function(e,f,g){return function(h,i,j,k){return f(this)[e](g(this),h,i,j,k)}}(c,r,s)
case 6:return function(e,f,g){return function(h,i,j,k,l){return f(this)[e](g(this),h,i,j,k,l)}}(c,r,s)
default:return function(e,f,g){return function(){var q=[g(this)]
Array.prototype.push.apply(q,arguments)
return e.apply(f(this),q)}}(d,r,s)}},
il(a,b,c){var s,r
if($.fP==null)$.fP=A.fO("interceptor")
if($.fQ==null)$.fQ=A.fO("receiver")
s=b.length
r=A.ik(s,c,a,b)
return r},
fB(a){return A.im(a)},
ig(a,b){return A.cl(v.typeUniverse,A.au(a.a),b)},
fR(a){return a.a},
ih(a){return a.b},
fO(a){var s,r,q,p=new A.b6("receiver","interceptor"),o=Object.getOwnPropertyNames(p)
o.$flags=1
s=o
for(o=s.length,r=0;r<o;++r){q=s[r]
if(p[q]===a)return q}throw A.b(A.cx("Field name "+a+" not found.",null))},
f0(a){return v.getIsolateTag(a)},
lf(a,b,c){Object.defineProperty(a,b,{value:c,enumerable:false,writable:true,configurable:true})},
kF(a){var s,r,q,p,o,n=A.aq($.hO.$1(a)),m=$.f_[n]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.f5[n]
if(s!=null)return s
r=v.interceptorsByTag[n]
if(r==null){q=A.eM($.hM.$2(a,n))
if(q!=null){m=$.f_[q]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.f5[q]
if(s!=null)return s
r=v.interceptorsByTag[q]
n=q}}if(r==null)return null
s=r.prototype
p=n[0]
if(p==="!"){m=A.f6(s)
$.f_[n]=m
Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}if(p==="~"){$.f5[n]=s
return s}if(p==="-"){o=A.f6(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}if(p==="+")return A.hR(a,s)
if(p==="*")throw A.b(A.hc(n))
if(v.leafTags[n]===true){o=A.f6(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}else return A.hR(a,s)},
hR(a,b){var s=Object.getPrototypeOf(a)
Object.defineProperty(s,v.dispatchPropertyName,{value:J.fJ(b,s,null,null),enumerable:false,writable:true,configurable:true})
return b},
f6(a){return J.fJ(a,!1,null,!!a.$iU)},
kH(a,b,c){var s=b.prototype
if(v.leafTags[a]===true)return A.f6(s)
else return J.fJ(s,c,null,null)},
kB(){if(!0===$.fG)return
$.fG=!0
A.kC()},
kC(){var s,r,q,p,o,n,m,l
$.f_=Object.create(null)
$.f5=Object.create(null)
A.kA()
s=v.interceptorsByTag
r=Object.getOwnPropertyNames(s)
if(typeof window!="undefined"){window
q=function(){}
for(p=0;p<r.length;++p){o=r[p]
n=$.hS.$1(o)
if(n!=null){m=A.kH(o,s[o],n)
if(m!=null){Object.defineProperty(n,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
q.prototype=n}}}}for(p=0;p<r.length;++p){o=r[p]
if(/^[A-Za-z_]/.test(o)){l=s[o]
s["!"+o]=l
s["~"+o]=l
s["-"+o]=l
s["+"+o]=l
s["*"+o]=l}}},
kA(){var s,r,q,p,o,n,m=B.a3()
m=A.bv(B.a4,A.bv(B.a5,A.bv(B.z,A.bv(B.z,A.bv(B.a6,A.bv(B.a7,A.bv(B.a8(B.y),m)))))))
if(typeof dartNativeDispatchHooksTransformer!="undefined"){s=dartNativeDispatchHooksTransformer
if(typeof s=="function")s=[s]
if(Array.isArray(s))for(r=0;r<s.length;++r){q=s[r]
if(typeof q=="function")m=q(m)||m}}p=m.getTag
o=m.getUnknownTag
n=m.prototypeForTag
$.hO=new A.f2(p)
$.hM=new A.f3(o)
$.hS=new A.f4(n)},
bv(a,b){return a(b)||b},
kp(a,b){var s=b.length,r=v.rttc[""+s+";"+a]
if(r==null)return null
if(s===0)return r
if(s===r.length)return r.apply(null,b)
return r(b)},
kw(a){if(a.indexOf("$",0)>=0)return a.replace(/\$/g,"$$$$")
return a},
hT(a){if(/[[\]{}()*+?.\\^$|]/.test(a))return a.replace(/[[\]{}()*+?.\\^$|]/g,"\\$&")
return a},
fK(a,b,c){var s=A.kO(a,b,c)
return s},
kO(a,b,c){var s,r,q
if(b===""){if(a==="")return c
s=a.length
for(r=c,q=0;q<s;++q)r=r+a[q]+c
return r.charCodeAt(0)==0?r:r}if(a.indexOf(b,0)<0)return a
if(a.length<500||c.indexOf("$",0)>=0)return a.split(b).join(c)
return a.replace(new RegExp(A.hT(b),"g"),A.kw(c))},
bq:function bq(a,b){this.a=a
this.b=b},
bY:function bY(){},
dW:function dW(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
bS:function bS(){},
cN:function cN(a,b,c){this.a=a
this.b=b
this.c=c},
d0:function d0(a){this.a=a},
dP:function dP(a){this.a=a},
bG:function bG(a,b){this.a=a
this.b=b},
cd:function cd(a){this.a=a
this.b=null},
aw:function aw(){},
cA:function cA(){},
cB:function cB(){},
cY:function cY(){},
cV:function cV(){},
b6:function b6(a,b){this.a=a
this.b=b},
cS:function cS(a){this.a=a},
aJ:function aJ(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
dG:function dG(a,b){this.a=a
this.b=b
this.c=null},
bO:function bO(a,b){this.a=a
this.$ti=b},
bN:function bN(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=null
_.$ti=d},
f2:function f2(a){this.a=a},
f3:function f3(a){this.a=a},
f4:function f4(a){this.a=a},
aY:function aY(){},
bp:function bp(){},
kP(a){throw A.y(A.fV(a),new Error())},
kQ(){throw A.y(A.fV(""),new Error())},
iZ(){var s=new A.ed()
return s.b=s},
ed:function ed(){this.b=null},
eR(a,b,c){},
L(a){return a},
iE(a,b,c){var s
A.eR(a,b,c)
s=new DataView(a,b,c)
return s},
h0(a){return new Uint8Array(a)},
iF(a,b,c){A.eR(a,b,c)
return c==null?new Uint8Array(a,b):new Uint8Array(a,b,c)},
ar(a,b,c){if(a>>>0!==a||a>=c)throw A.b(A.eZ(b,a))},
aE(a,b,c){var s
if(!(a>>>0!==a))s=b>>>0!==b||a>b||b>c
else s=!0
if(s)throw A.b(A.ku(a,b,c))
return b},
ay:function ay(){},
bb:function bb(){},
bR:function bR(){},
dh:function dh(a){this.a=a},
aN:function aN(){},
C:function C(){},
bQ:function bQ(){},
V:function V(){},
bc:function bc(){},
bd:function bd(){},
be:function be(){},
bf:function bf(){},
bg:function bg(){},
bh:function bh(){},
bi:function bi(){},
aO:function aO(){},
az:function az(){},
c8:function c8(){},
c9:function c9(){},
ca:function ca(){},
cb:function cb(){},
fk(a,b){var s=b.c
return s==null?b.c=A.cj(a,"J",[b.x]):s},
h7(a){var s=a.w
if(s===6||s===7)return A.h7(a.x)
return s===11||s===12},
iM(a){return a.as},
as(a){return A.eC(v.typeUniverse,a,!1)},
b0(a1,a2,a3,a4){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=a2.w
switch(a0){case 5:case 1:case 2:case 3:case 4:return a2
case 6:s=a2.x
r=A.b0(a1,s,a3,a4)
if(r===s)return a2
return A.hm(a1,r,!0)
case 7:s=a2.x
r=A.b0(a1,s,a3,a4)
if(r===s)return a2
return A.hl(a1,r,!0)
case 8:q=a2.y
p=A.bu(a1,q,a3,a4)
if(p===q)return a2
return A.cj(a1,a2.x,p)
case 9:o=a2.x
n=A.b0(a1,o,a3,a4)
m=a2.y
l=A.bu(a1,m,a3,a4)
if(n===o&&l===m)return a2
return A.fq(a1,n,l)
case 10:k=a2.x
j=a2.y
i=A.bu(a1,j,a3,a4)
if(i===j)return a2
return A.hn(a1,k,i)
case 11:h=a2.x
g=A.b0(a1,h,a3,a4)
f=a2.y
e=A.kd(a1,f,a3,a4)
if(g===h&&e===f)return a2
return A.hk(a1,g,e)
case 12:d=a2.y
a4+=d.length
c=A.bu(a1,d,a3,a4)
o=a2.x
n=A.b0(a1,o,a3,a4)
if(c===d&&n===o)return a2
return A.fr(a1,n,c,!0)
case 13:b=a2.x
if(b<a4)return a2
a=a3[b-a4]
if(a==null)return a2
return a
default:throw A.b(A.cz("Attempted to substitute unexpected RTI kind "+a0))}},
bu(a,b,c,d){var s,r,q,p,o=b.length,n=A.eH(o)
for(s=!1,r=0;r<o;++r){q=b[r]
p=A.b0(a,q,c,d)
if(p!==q)s=!0
n[r]=p}return s?n:b},
ke(a,b,c,d){var s,r,q,p,o,n,m=b.length,l=A.eH(m)
for(s=!1,r=0;r<m;r+=3){q=b[r]
p=b[r+1]
o=b[r+2]
n=A.b0(a,o,c,d)
if(n!==o)s=!0
l.splice(r,3,q,p,n)}return s?l:b},
kd(a,b,c,d){var s,r=b.a,q=A.bu(a,r,c,d),p=b.b,o=A.bu(a,p,c,d),n=b.c,m=A.ke(a,n,c,d)
if(q===r&&o===p&&m===n)return b
s=new A.dc()
s.a=q
s.b=o
s.c=m
return s},
f(a,b){a[v.arrayRti]=b
return a},
fC(a){var s=a.$S
if(s!=null){if(typeof s=="number")return A.kz(s)
return a.$S()}return null},
kD(a,b){var s
if(A.h7(b))if(a instanceof A.aw){s=A.fC(a)
if(s!=null)return s}return A.au(a)},
au(a){if(a instanceof A.d)return A.B(a)
if(Array.isArray(a))return A.a9(a)
return A.fu(J.at(a))},
a9(a){var s=a[v.arrayRti],r=t.gn
if(s==null)return r
if(s.constructor!==r.constructor)return r
return s},
B(a){var s=a.$ti
return s!=null?s:A.fu(a)},
fu(a){var s=a.constructor,r=s.$ccache
if(r!=null)return r
return A.jE(a,s)},
jE(a,b){var s=a instanceof A.aw?Object.getPrototypeOf(Object.getPrototypeOf(a)).constructor:b,r=A.jh(v.typeUniverse,s.name)
b.$ccache=r
return r},
kz(a){var s,r=v.types,q=r[a]
if(typeof q=="string"){s=A.eC(v.typeUniverse,q,!1)
r[a]=s
return s}return q},
fF(a){return A.ab(A.B(a))},
fz(a){var s
if(a instanceof A.aY)return a.b7()
s=a instanceof A.aw?A.fC(a):null
if(s!=null)return s
if(t.dm.b(a))return J.bz(a).a
if(Array.isArray(a))return A.a9(a)
return A.au(a)},
ab(a){var s=a.r
return s==null?a.r=new A.eB(a):s},
kx(a,b){var s,r,q=b,p=q.length
if(p===0)return t.bQ
if(0>=p)return A.a(q,0)
s=A.cl(v.typeUniverse,A.fz(q[0]),"@<0>")
for(r=1;r<p;++r){if(!(r<q.length))return A.a(q,r)
s=A.hp(v.typeUniverse,s,A.fz(q[r]))}return A.cl(v.typeUniverse,s,a)},
a0(a){return A.ab(A.eC(v.typeUniverse,a,!1))},
jD(a){var s=this
s.b=A.kb(s)
return s.b(a)},
kb(a){var s,r,q,p,o
if(a===t.K)return A.jN
if(A.b3(a))return A.jS
s=a.w
if(s===6)return A.jB
if(s===1)return A.hG
if(s===7)return A.jI
r=A.ka(a)
if(r!=null)return r
if(s===8){q=a.x
if(a.y.every(A.b3)){a.f="$i"+q
if(q==="k")return A.jL
if(a===t.m)return A.jK
return A.jR}}else if(s===10){p=A.kp(a.x,a.y)
o=p==null?A.hG:p
return o==null?A.ap(o):o}return A.jz},
ka(a){if(a.w===8){if(a===t.S)return A.co
if(a===t.i||a===t.o)return A.jM
if(a===t.N)return A.jQ
if(a===t.y)return A.dk}return null},
jC(a){var s=this,r=A.jy
if(A.b3(s))r=A.jp
else if(s===t.K)r=A.ap
else if(A.bx(s)){r=A.jA
if(s===t.h6)r=A.jo
else if(s===t.c8)r=A.eM
else if(s===t.fQ)r=A.jm
else if(s===t.cg)r=A.hx
else if(s===t.I)r=A.jn
else if(s===t.bX)r=A.hv}else if(s===t.S)r=A.aa
else if(s===t.N)r=A.aq
else if(s===t.y)r=A.hu
else if(s===t.o)r=A.hw
else if(s===t.i)r=A.dj
else if(s===t.m)r=A.b_
s.a=r
return s.a(a)},
jz(a){var s=this
if(a==null)return A.bx(s)
return A.kE(v.typeUniverse,A.kD(a,s),s)},
jB(a){if(a==null)return!0
return this.x.b(a)},
jR(a){var s,r=this
if(a==null)return A.bx(r)
s=r.f
if(a instanceof A.d)return!!a[s]
return!!J.at(a)[s]},
jL(a){var s,r=this
if(a==null)return A.bx(r)
if(typeof a!="object")return!1
if(Array.isArray(a))return!0
s=r.f
if(a instanceof A.d)return!!a[s]
return!!J.at(a)[s]},
jK(a){var s=this
if(a==null)return!1
if(typeof a=="object"){if(a instanceof A.d)return!!a[s.f]
return!0}if(typeof a=="function")return!0
return!1},
hF(a){if(typeof a=="object"){if(a instanceof A.d)return t.m.b(a)
return!0}if(typeof a=="function")return!0
return!1},
jy(a){var s=this
if(a==null){if(A.bx(s))return a}else if(s.b(a))return a
throw A.y(A.hz(a,s),new Error())},
jA(a){var s=this
if(a==null||s.b(a))return a
throw A.y(A.hz(a,s),new Error())},
hz(a,b){return new A.ch("TypeError: "+A.he(a,A.M(b,null)))},
he(a,b){return A.cH(a)+": type '"+A.M(A.fz(a),null)+"' is not a subtype of type '"+b+"'"},
a_(a,b){return new A.ch("TypeError: "+A.he(a,b))},
jI(a){var s=this
return s.x.b(a)||A.fk(v.typeUniverse,s).b(a)},
jN(a){return a!=null},
ap(a){if(a!=null)return a
throw A.y(A.a_(a,"Object"),new Error())},
jS(a){return!0},
jp(a){return a},
hG(a){return!1},
dk(a){return!0===a||!1===a},
hu(a){if(!0===a)return!0
if(!1===a)return!1
throw A.y(A.a_(a,"bool"),new Error())},
jm(a){if(!0===a)return!0
if(!1===a)return!1
if(a==null)return a
throw A.y(A.a_(a,"bool?"),new Error())},
dj(a){if(typeof a=="number")return a
throw A.y(A.a_(a,"double"),new Error())},
jn(a){if(typeof a=="number")return a
if(a==null)return a
throw A.y(A.a_(a,"double?"),new Error())},
co(a){return typeof a=="number"&&Math.floor(a)===a},
aa(a){if(typeof a=="number"&&Math.floor(a)===a)return a
throw A.y(A.a_(a,"int"),new Error())},
jo(a){if(typeof a=="number"&&Math.floor(a)===a)return a
if(a==null)return a
throw A.y(A.a_(a,"int?"),new Error())},
jM(a){return typeof a=="number"},
hw(a){if(typeof a=="number")return a
throw A.y(A.a_(a,"num"),new Error())},
hx(a){if(typeof a=="number")return a
if(a==null)return a
throw A.y(A.a_(a,"num?"),new Error())},
jQ(a){return typeof a=="string"},
aq(a){if(typeof a=="string")return a
throw A.y(A.a_(a,"String"),new Error())},
eM(a){if(typeof a=="string")return a
if(a==null)return a
throw A.y(A.a_(a,"String?"),new Error())},
b_(a){if(A.hF(a))return a
throw A.y(A.a_(a,"JSObject"),new Error())},
hv(a){if(a==null)return a
if(A.hF(a))return a
throw A.y(A.a_(a,"JSObject?"),new Error())},
hJ(a,b){var s,r,q
for(s="",r="",q=0;q<a.length;++q,r=", ")s+=r+A.M(a[q],b)
return s},
k4(a,b){var s,r,q,p,o,n,m=a.x,l=a.y
if(""===m)return"("+A.hJ(l,b)+")"
s=l.length
r=m.split(",")
q=r.length-s
for(p="(",o="",n=0;n<s;++n,o=", "){p+=o
if(q===0)p+="{"
p+=A.M(l[n],b)
if(q>=0)p+=" "+r[q];++q}return p+"})"},
hC(a3,a4,a5){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1=", ",a2=null
if(a5!=null){s=a5.length
if(a4==null)a4=A.f([],t.s)
else a2=a4.length
r=a4.length
for(q=s;q>0;--q)B.a.j(a4,"T"+(r+q))
for(p=t.X,o="<",n="",q=0;q<s;++q,n=a1){m=a4.length
l=m-1-q
if(!(l>=0))return A.a(a4,l)
o=o+n+a4[l]
k=a5[q]
j=k.w
if(!(j===2||j===3||j===4||j===5||k===p))o+=" extends "+A.M(k,a4)}o+=">"}else o=""
p=a3.x
i=a3.y
h=i.a
g=h.length
f=i.b
e=f.length
d=i.c
c=d.length
b=A.M(p,a4)
for(a="",a0="",q=0;q<g;++q,a0=a1)a+=a0+A.M(h[q],a4)
if(e>0){a+=a0+"["
for(a0="",q=0;q<e;++q,a0=a1)a+=a0+A.M(f[q],a4)
a+="]"}if(c>0){a+=a0+"{"
for(a0="",q=0;q<c;q+=3,a0=a1){a+=a0
if(d[q+1])a+="required "
a+=A.M(d[q+2],a4)+" "+d[q]}a+="}"}if(a2!=null){a4.toString
a4.length=a2}return o+"("+a+") => "+b},
M(a,b){var s,r,q,p,o,n,m,l=a.w
if(l===5)return"erased"
if(l===2)return"dynamic"
if(l===3)return"void"
if(l===1)return"Never"
if(l===4)return"any"
if(l===6){s=a.x
r=A.M(s,b)
q=s.w
return(q===11||q===12?"("+r+")":r)+"?"}if(l===7)return"FutureOr<"+A.M(a.x,b)+">"
if(l===8){p=A.kg(a.x)
o=a.y
return o.length>0?p+("<"+A.hJ(o,b)+">"):p}if(l===10)return A.k4(a,b)
if(l===11)return A.hC(a,b,null)
if(l===12)return A.hC(a.x,b,a.y)
if(l===13){n=a.x
m=b.length
n=m-1-n
if(!(n>=0&&n<m))return A.a(b,n)
return b[n]}return"?"},
kg(a){var s=A.hU(a)
if(s!=null)return s
return"minified:"+a},
ji(a,b){var s=a.tR[b]
while(typeof s=="string")s=a.tR[s]
return s},
jh(a,b){var s,r,q,p,o,n=a.eT,m=n[b]
if(m==null)return A.eC(a,b,!1)
else if(typeof m=="number"){s=m
r=A.ck(a,5,"#")
q=A.eH(s)
for(p=0;p<s;++p)q[p]=r
o=A.cj(a,b,q)
n[b]=o
return o}else return m},
jg(a,b){return A.hr(a.tR,b)},
jf(a,b){return A.hr(a.eT,b)},
eC(a,b,c){var s,r=a.eC,q=r.get(b)
if(q!=null)return q
s=A.ho(a,null,b,!1)
r.set(b,s)
return s},
cl(a,b,c){var s,r,q=b.z
if(q==null)q=b.z=new Map()
s=q.get(c)
if(s!=null)return s
r=A.ho(a,b,c,!0)
q.set(c,r)
return r},
hp(a,b,c){var s,r,q,p=b.Q
if(p==null)p=b.Q=new Map()
s=c.as
r=p.get(s)
if(r!=null)return r
q=A.fq(a,b,c.w===9?c.y:[c])
p.set(s,q)
return q},
ho(a,b,c,d){return A.j7(A.j1(a,b,c,d))},
aD(a,b){b.a=A.jC
b.b=A.jD
return b},
ck(a,b,c){var s,r,q=a.eC.get(c)
if(q!=null)return q
s=new A.a5(null,null)
s.w=b
s.as=c
r=A.aD(a,s)
a.eC.set(c,r)
return r},
hm(a,b,c){var s,r=b.as+"?",q=a.eC.get(r)
if(q!=null)return q
s=A.jd(a,b,r,c)
a.eC.set(r,s)
return s},
jd(a,b,c,d){var s,r,q
if(d){s=b.w
r=!0
if(!A.b3(b))if(!(b===t.P||b===t.T))if(s!==6)r=s===7&&A.bx(b.x)
if(r)return b
else if(s===1)return t.P}q=new A.a5(null,null)
q.w=6
q.x=b
q.as=c
return A.aD(a,q)},
hl(a,b,c){var s,r=b.as+"/",q=a.eC.get(r)
if(q!=null)return q
s=A.jb(a,b,r,c)
a.eC.set(r,s)
return s},
jb(a,b,c,d){var s,r
if(d){s=b.w
if(A.b3(b)||b===t.K)return b
else if(s===1)return A.cj(a,"J",[b])
else if(b===t.P||b===t.T)return t.eH}r=new A.a5(null,null)
r.w=7
r.x=b
r.as=c
return A.aD(a,r)},
je(a,b){var s,r,q=""+b+"^",p=a.eC.get(q)
if(p!=null)return p
s=new A.a5(null,null)
s.w=13
s.x=b
s.as=q
r=A.aD(a,s)
a.eC.set(q,r)
return r},
ci(a){var s,r,q,p=a.length
for(s="",r="",q=0;q<p;++q,r=",")s+=r+a[q].as
return s},
ja(a){var s,r,q,p,o,n=a.length
for(s="",r="",q=0;q<n;q+=3,r=","){p=a[q]
o=a[q+1]?"!":":"
s+=r+p+o+a[q+2].as}return s},
cj(a,b,c){var s,r,q,p=b
if(c.length>0)p+="<"+A.ci(c)+">"
s=a.eC.get(p)
if(s!=null)return s
r=new A.a5(null,null)
r.w=8
r.x=b
r.y=c
if(c.length>0)r.c=c[0]
r.as=p
q=A.aD(a,r)
a.eC.set(p,q)
return q},
fq(a,b,c){var s,r,q,p,o,n
if(b.w===9){s=b.x
r=b.y.concat(c)}else{r=c
s=b}q=s.as+(";<"+A.ci(r)+">")
p=a.eC.get(q)
if(p!=null)return p
o=new A.a5(null,null)
o.w=9
o.x=s
o.y=r
o.as=q
n=A.aD(a,o)
a.eC.set(q,n)
return n},
hn(a,b,c){var s,r,q="+"+(b+"("+A.ci(c)+")"),p=a.eC.get(q)
if(p!=null)return p
s=new A.a5(null,null)
s.w=10
s.x=b
s.y=c
s.as=q
r=A.aD(a,s)
a.eC.set(q,r)
return r},
hk(a,b,c){var s,r,q,p,o,n=b.as,m=c.a,l=m.length,k=c.b,j=k.length,i=c.c,h=i.length,g="("+A.ci(m)
if(j>0){s=l>0?",":""
g+=s+"["+A.ci(k)+"]"}if(h>0){s=l>0?",":""
g+=s+"{"+A.ja(i)+"}"}r=n+(g+")")
q=a.eC.get(r)
if(q!=null)return q
p=new A.a5(null,null)
p.w=11
p.x=b
p.y=c
p.as=r
o=A.aD(a,p)
a.eC.set(r,o)
return o},
fr(a,b,c,d){var s,r=b.as+("<"+A.ci(c)+">"),q=a.eC.get(r)
if(q!=null)return q
s=A.jc(a,b,c,r,d)
a.eC.set(r,s)
return s},
jc(a,b,c,d,e){var s,r,q,p,o,n,m,l
if(e){s=c.length
r=A.eH(s)
for(q=0,p=0;p<s;++p){o=c[p]
if(o.w===1){r[p]=o;++q}}if(q>0){n=A.b0(a,b,r,0)
m=A.bu(a,c,r,0)
return A.fr(a,n,m,c!==m)}}l=new A.a5(null,null)
l.w=12
l.x=b
l.y=c
l.as=d
return A.aD(a,l)},
j1(a,b,c,d){return{u:a,e:b,r:c,s:[],p:0,n:d}},
j7(a){var s,r,q,p,o,n,m,l=a.r,k=a.s
for(s=l.length,r=0;r<s;){q=l.charCodeAt(r)
if(q>=48&&q<=57)r=A.j3(r+1,q,l,k)
else if((((q|32)>>>0)-97&65535)<26||q===95||q===36||q===124)r=A.hg(a,r,l,k,!1)
else if(q===46)r=A.hg(a,r,l,k,!0)
else{++r
switch(q){case 44:break
case 58:k.push(!1)
break
case 33:k.push(!0)
break
case 59:k.push(A.aX(a.u,a.e,k.pop()))
break
case 94:k.push(A.je(a.u,k.pop()))
break
case 35:k.push(A.ck(a.u,5,"#"))
break
case 64:k.push(A.ck(a.u,2,"@"))
break
case 126:k.push(A.ck(a.u,3,"~"))
break
case 60:k.push(a.p)
a.p=k.length
break
case 62:A.j5(a,k)
break
case 38:A.j4(a,k)
break
case 63:p=a.u
k.push(A.hm(p,A.aX(p,a.e,k.pop()),a.n))
break
case 47:p=a.u
k.push(A.hl(p,A.aX(p,a.e,k.pop()),a.n))
break
case 40:k.push(-3)
k.push(a.p)
a.p=k.length
break
case 41:A.j2(a,k)
break
case 91:k.push(a.p)
a.p=k.length
break
case 93:o=k.splice(a.p)
A.hh(a.u,a.e,o)
a.p=k.pop()
k.push(o)
k.push(-1)
break
case 123:k.push(a.p)
a.p=k.length
break
case 125:o=k.splice(a.p)
A.j8(a.u,a.e,o)
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
return A.aX(a.u,a.e,m)},
j3(a,b,c,d){var s,r,q=b-48
for(s=c.length;a<s;++a){r=c.charCodeAt(a)
if(!(r>=48&&r<=57))break
q=q*10+(r-48)}d.push(q)
return a},
hg(a,b,c,d,e){var s,r,q,p,o,n,m=b+1
for(s=c.length;m<s;++m){r=c.charCodeAt(m)
if(r===46){if(e)break
e=!0}else{if(!((((r|32)>>>0)-97&65535)<26||r===95||r===36||r===124))q=r>=48&&r<=57
else q=!0
if(!q)break}}p=c.substring(b,m)
if(e){s=a.u
o=a.e
if(o.w===9)o=o.x
n=A.ji(s,o.x)[p]
if(n==null)A.n('No "'+p+'" in "'+A.iM(o)+'"')
d.push(A.cl(s,o,n))}else d.push(p)
return m},
j5(a,b){var s,r=a.u,q=A.hf(a,b),p=b.pop()
if(typeof p=="string")b.push(A.cj(r,p,q))
else{s=A.aX(r,a.e,p)
switch(s.w){case 11:b.push(A.fr(r,s,q,a.n))
break
default:b.push(A.fq(r,s,q))
break}}},
j2(a,b){var s,r,q,p=a.u,o=b.pop(),n=null,m=null
if(typeof o=="number")switch(o){case-1:n=b.pop()
break
case-2:m=b.pop()
break
default:b.push(o)
break}else b.push(o)
s=A.hf(a,b)
o=b.pop()
switch(o){case-3:o=b.pop()
if(n==null)n=p.sEA
if(m==null)m=p.sEA
r=A.aX(p,a.e,o)
q=new A.dc()
q.a=s
q.b=n
q.c=m
b.push(A.hk(p,r,q))
return
case-4:b.push(A.hn(p,b.pop(),s))
return
default:throw A.b(A.cz("Unexpected state under `()`: "+A.p(o)))}},
j4(a,b){var s=b.pop()
if(0===s){b.push(A.ck(a.u,1,"0&"))
return}if(1===s){b.push(A.ck(a.u,4,"1&"))
return}throw A.b(A.cz("Unexpected extended operation "+A.p(s)))},
hf(a,b){var s=b.splice(a.p)
A.hh(a.u,a.e,s)
a.p=b.pop()
return s},
aX(a,b,c){if(typeof c=="string")return A.cj(a,c,a.sEA)
else if(typeof c=="number"){b.toString
return A.j6(a,b,c)}else return c},
hh(a,b,c){var s,r=c.length
for(s=0;s<r;++s)c[s]=A.aX(a,b,c[s])},
j8(a,b,c){var s,r=c.length
for(s=2;s<r;s+=3)c[s]=A.aX(a,b,c[s])},
j6(a,b,c){var s,r,q=b.w
if(q===9){if(c===0)return b.x
s=b.y
r=s.length
if(c<=r)return s[c-1]
c-=r
b=b.x
q=b.w}else if(c===0)return b
if(q!==8)throw A.b(A.cz("Indexed base must be an interface type"))
s=b.y
if(c<=s.length)return s[c-1]
throw A.b(A.cz("Bad index "+c+" for "+b.i(0)))},
kE(a,b,c){var s,r=b.d
if(r==null)r=b.d=new Map()
s=r.get(c)
if(s==null){s=A.x(a,b,null,c,null)
r.set(c,s)}return s},
x(a,b,c,d,e){var s,r,q,p,o,n,m,l,k,j,i
if(b===d)return!0
if(A.b3(d))return!0
s=b.w
if(s===4)return!0
if(A.b3(b))return!1
if(b.w===1)return!0
r=s===13
if(r)if(A.x(a,c[b.x],c,d,e))return!0
q=d.w
p=t.P
if(b===p||b===t.T){if(q===7)return A.x(a,b,c,d.x,e)
return d===p||d===t.T||q===6}if(d===t.K){if(s===7)return A.x(a,b.x,c,d,e)
return s!==6}if(s===7){if(!A.x(a,b.x,c,d,e))return!1
return A.x(a,A.fk(a,b),c,d,e)}if(s===6)return A.x(a,p,c,d,e)&&A.x(a,b.x,c,d,e)
if(q===7){if(A.x(a,b,c,d.x,e))return!0
return A.x(a,b,c,A.fk(a,d),e)}if(q===6)return A.x(a,b,c,p,e)||A.x(a,b,c,d.x,e)
if(r)return!1
p=s!==11
if((!p||s===12)&&d===t.Z)return!0
o=s===10
if(o&&d===t.gT)return!0
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
if(!A.x(a,j,c,i,e)||!A.x(a,i,e,j,c))return!1}return A.hE(a,b.x,c,d.x,e)}if(q===11){if(b===t.g)return!0
if(p)return!1
return A.hE(a,b,c,d,e)}if(s===8){if(q!==8)return!1
return A.jJ(a,b,c,d,e)}if(o&&q===10)return A.jP(a,b,c,d,e)
return!1},
hE(a3,a4,a5,a6,a7){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2
if(!A.x(a3,a4.x,a5,a6.x,a7))return!1
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
if(!A.x(a3,p[h],a7,g,a5))return!1}for(h=0;h<m;++h){g=l[h]
if(!A.x(a3,p[o+h],a7,g,a5))return!1}for(h=0;h<i;++h){g=l[m+h]
if(!A.x(a3,k[h],a7,g,a5))return!1}f=s.c
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
if(!A.x(a3,e[a+2],a7,g,a5))return!1
break}}while(b<d){if(f[b+1])return!1
b+=3}return!0},
jJ(a,b,c,d,e){var s,r,q,p,o,n=b.x,m=d.x
while(n!==m){s=a.tR[n]
if(s==null)return!1
if(typeof s=="string"){n=s
continue}r=s[m]
if(r==null)return!1
q=r.length
p=q>0?new Array(q):v.typeUniverse.sEA
for(o=0;o<q;++o)p[o]=A.cl(a,b,r[o])
return A.ht(a,p,null,c,d.y,e)}return A.ht(a,b.y,null,c,d.y,e)},
ht(a,b,c,d,e,f){var s,r=b.length
for(s=0;s<r;++s)if(!A.x(a,b[s],d,e[s],f))return!1
return!0},
jP(a,b,c,d,e){var s,r=b.y,q=d.y,p=r.length
if(p!==q.length)return!1
if(b.x!==d.x)return!1
for(s=0;s<p;++s)if(!A.x(a,r[s],c,q[s],e))return!1
return!0},
bx(a){var s=a.w,r=!0
if(!(a===t.P||a===t.T))if(!A.b3(a))if(s!==6)r=s===7&&A.bx(a.x)
return r},
b3(a){var s=a.w
return s===2||s===3||s===4||s===5||a===t.X},
hr(a,b){var s,r,q=Object.keys(b),p=q.length
for(s=0;s<p;++s){r=q[s]
a[r]=b[r]}},
eH(a){return a>0?new Array(a):v.typeUniverse.sEA},
a5:function a5(a,b){var _=this
_.a=a
_.b=b
_.r=_.f=_.d=_.c=null
_.w=0
_.as=_.Q=_.z=_.y=_.x=null},
dc:function dc(){this.c=this.b=this.a=null},
eB:function eB(a){this.a=a},
db:function db(){},
ch:function ch(a){this.a=a},
iU(){var s,r,q
if(self.scheduleImmediate!=null)return A.kj()
if(self.MutationObserver!=null&&self.document!=null){s={}
r=self.document.createElement("div")
q=self.document.createElement("span")
s.a=null
new self.MutationObserver(A.dp(new A.e9(s),1)).observe(r,{childList:true})
return new A.e8(s,r,q)}else if(self.setImmediate!=null)return A.kk()
return A.kl()},
iV(a){self.scheduleImmediate(A.dp(new A.ea(t.M.a(a)),0))},
iW(a){self.setImmediate(A.dp(new A.eb(t.M.a(a)),0))},
iX(a){t.M.a(a)
A.j9(0,a)},
j9(a,b){var s=new A.ez()
s.bK(a,b)
return s},
G(a){return new A.c3(new A.j($.i,a.h("j<0>")),a.h("c3<0>"))},
F(a,b){a.$2(0,null)
b.b=!0
return b.a},
cn(a,b){A.js(a,b)},
E(a,b){b.aL(a)},
D(a,b){b.bn(A.P(a),A.S(a))},
js(a,b){var s,r,q=new A.eO(b),p=new A.eP(b)
if(a instanceof A.j)a.bh(q,p,t.z)
else{s=t.z
if(a instanceof A.j)a.ak(q,p,s)
else{r=new A.j($.i,t._)
r.a=8
r.c=a
r.bh(q,p,s)}}},
H(a){var s=function(b,c){return function(d,e){while(true){try{b(d,e)
break}catch(q){e=q
d=c}}}}(a,1),r=$.i
return r.aE(r,t.as.a(new A.eX(s)),t.H,t.S,t.z)},
hj(a,b,c){return 0},
dv(a){var s
if(t.Q.b(a)){s=a.gaq()
if(s!=null)return s}return B.B},
is(a,b){var s,r,q,p,o,n,m,l=null
try{l=a.$0()}catch(q){s=A.P(q)
r=A.S(q)
p=new A.j($.i,b.h("j<0>"))
o=s
n=r
m=A.hD(o,n)
o=new A.N(o,n==null?A.dv(o):n)
p.R(o)
return p}return b.h("J<0>").b(l)?l:A.fn(l,b)},
hD(a,b){var s=$.i
if(s===B.d)return null
s.bV(s,a,b)
return null},
jF(a,b){if($.i!==B.d)A.hD(a,b)
if(t.Q.b(a))A.iL(a,b)
return new A.N(a,b)},
fn(a,b){var s=new A.j($.i,b.h("j<0>"))
b.a(a)
s.a=8
s.c=a
return s},
fo(a,b,c){var s,r,q,p,o,n={},m=n.a=a
for(s=t._;r=m.a,(r&4)!==0;m=a){a=s.a(m.c)
n.a=a}if(m===b){s=A.iN()
b.R(new A.N(new A.a1(!0,m,null,"Cannot complete a future with itself"),s))
return}q=b.a&1
s=m.a=r|q
if((s&24)===0){p=t.F.a(b.c)
b.a=b.a&1|4
b.c=m
m.bd(p)
return}if(!c)if(b.c==null)m=(s&16)===0||q!==0
else m=!1
else m=!0
if(m){p=b.U()
b.a8(n.a)
A.aW(b,p)
return}b.a^=2
o=b.b
o.V(o,new A.ej(n,b))},
aW(a,b){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e={},d=e.a=a
for(s=t.n,r=t.F;;){q={}
p=d.a
o=(p&16)===0
n=!o
if(b==null){if(n&&(p&1)===0){m=s.a(d.c)
d=d.b
d.S(d,m.a,m.b)}return}q.a=b
l=b.a
for(d=b;l!=null;d=l,l=k){d.a=null
A.aW(e.a,d)
q.a=l
k=l.a}j=e.a.c
q.b=n
q.c=j
if(o){p=d.c
p=(p&1)!==0||(p&15)===8}else p=!0
if(p){i=d.b.b
h=$.i
if(h!==i)$.i=i
else h=null
d=d.c
if((d&15)===8)new A.en(q,e,n).$0()
else if(o){if((d&1)!==0)new A.em(q,j).$0()}else if((d&2)!==0)new A.el(e,q).$0()
if(h!=null)$.i=h
d=q.c
if(d instanceof A.j){p=q.a.$ti
p=p.h("J<2>").b(d)||!p.y[1].b(d)}else p=!1
if(p){g=q.a.b
if((d.a&24)!==0){f=r.a(g.c)
g.c=null
b=g.ad(f)
g.a=d.a&30|g.a&1
g.c=d.c
e.a=d
continue}else A.fo(d,g,!0)
return}}g=q.a.b
f=r.a(g.c)
g.c=null
b=g.ad(f)
d=q.b
p=q.c
if(!d){g.$ti.c.a(p)
g.a=8
g.c=p}else{s.a(p)
g.a=g.a&1|16
g.c=p}e.a=g
d=g}},
k5(a,b){var s=t.C
if(s.b(a))return b.aE(b,s.a(a),t.z,t.K,t.l)
s=t.v
if(s.b(a))return b.ac(b,s.a(a),t.z,t.K)
throw A.b(A.av(a,"onError",u.c))},
jU(){var s,r
for(s=$.bs;s!=null;s=$.bs){$.cq=null
r=s.b
$.bs=r
if(r==null)$.cp=null
s.a.$0()}},
kc(){$.fv=!0
try{A.jU()}finally{$.cq=null
$.fv=!1
if($.bs!=null)$.fN().$1(A.hN())}},
hK(a){var s=new A.d2(a),r=$.cp
if(r==null){$.bs=$.cp=s
if(!$.fv)$.fN().$1(A.hN())}else $.cp=r.b=s},
k9(a){var s,r,q,p=$.bs
if(p==null){A.hK(a)
$.cq=$.cp
return}s=new A.d2(a)
r=$.cq
if(r==null){s.b=p
$.bs=$.cq=s}else{q=r.b
s.b=q
$.cq=r.b=s
if(q==null)$.cp=s}},
kN(a){var s=$.i
if(B.d===s){A.fx(B.d,a)
return}A.fx(s,s.ab(s,a,t.H))
return},
kX(a,b){A.dn(a,"stream",t.K)
return new A.df(b.h("df<0>"))},
h9(a){var s=null
return new A.bm(s,s,s,s,a.h("bm<0>"))},
fy(a){return},
iY(a,b){if(b==null)b=A.km()
if(t.da.b(b))return a.aE(a,t.C.a(b),t.z,t.K,t.l)
if(t.d5.b(b))return a.ac(a,t.v.a(b),t.z,t.K)
throw A.b(A.cx("handleError callback must take either an Object (the error), or both an Object (the error) and a StackTrace.",null))},
jV(a,b){var s
A.ap(a)
t.l.a(b)
s=$.i
s.S(s,a,b)},
k7(a,b){A.k9(new A.eU(a,b))},
fx(a,b){if(B.d!==a)b=a.cg(b,t.H)
A.hK(b)},
e9:function e9(a){this.a=a},
e8:function e8(a,b,c){this.a=a
this.b=b
this.c=c},
ea:function ea(a){this.a=a},
eb:function eb(a){this.a=a},
ez:function ez(){},
eA:function eA(a,b){this.a=a
this.b=b},
c3:function c3(a,b){this.a=a
this.b=!1
this.$ti=b},
eO:function eO(a){this.a=a},
eP:function eP(a){this.a=a},
eX:function eX(a){this.a=a},
A:function A(a,b){var _=this
_.a=a
_.e=_.d=_.c=_.b=null
_.$ti=b},
br:function br(a,b){this.a=a
this.$ti=b},
N:function N(a,b){this.a=a
this.b=b},
c5:function c5(){},
bl:function bl(a,b){this.a=a
this.$ti=b},
an:function an(a,b,c,d,e){var _=this
_.a=null
_.b=a
_.c=b
_.d=c
_.e=d
_.$ti=e},
j:function j(a,b){var _=this
_.a=0
_.b=a
_.c=null
_.$ti=b},
eg:function eg(a,b){this.a=a
this.b=b},
ek:function ek(a,b){this.a=a
this.b=b},
ej:function ej(a,b){this.a=a
this.b=b},
ei:function ei(a,b){this.a=a
this.b=b},
eh:function eh(a,b){this.a=a
this.b=b},
en:function en(a,b,c){this.a=a
this.b=b
this.c=c},
eo:function eo(a,b){this.a=a
this.b=b},
ep:function ep(a){this.a=a},
em:function em(a,b){this.a=a
this.b=b},
el:function el(a,b){this.a=a
this.b=b},
d2:function d2(a){this.a=a
this.b=null},
c_:function c_(){},
dT:function dT(a,b){this.a=a
this.b=b},
dU:function dU(a,b){this.a=a
this.b=b},
ce:function ce(){},
ey:function ey(a){this.a=a},
ex:function ex(a){this.a=a},
d3:function d3(){},
bm:function bm(a,b,c,d,e){var _=this
_.a=null
_.b=0
_.c=null
_.d=a
_.e=b
_.f=c
_.r=d
_.$ti=e},
bn:function bn(a,b){this.a=a
this.$ti=b},
bo:function bo(a,b,c,d,e,f){var _=this
_.w=a
_.a=b
_.c=c
_.d=d
_.e=e
_.r=_.f=null
_.$ti=f},
c4:function c4(){},
ec:function ec(a){this.a=a},
cg:function cg(){},
aC:function aC(){},
aU:function aU(a,b){this.b=a
this.a=null
this.$ti=b},
d8:function d8(){},
a8:function a8(a){var _=this
_.a=0
_.c=_.b=null
_.$ti=a},
ev:function ev(a,b){this.a=a
this.b=b},
df:function df(a){this.$ti=a},
e5:function e5(){},
e6:function e6(a,b,c){this.a=a
this.b=b
this.c=c},
eU:function eU(a,b){this.a=a
this.b=b},
fY(a,b,c){return b.h("@<0>").B(c).h("fW<1,2>").a(A.ky(a,new A.aJ(b.h("@<0>").B(c).h("aJ<1,2>"))))},
fX(a,b){return new A.aJ(a.h("@<0>").B(b).h("aJ<1,2>"))},
iw(a){return new A.c6(a.h("c6<0>"))},
fp(){var s=Object.create(null)
s["<non-identifier-key>"]=s
delete s["<non-identifier-key>"]
return s},
fZ(a){var s,r
if(A.fI(a))return"{...}"
s=new A.aQ("")
try{r={}
B.a.j($.Y,a)
s.a+="{"
r.a=!0
a.Y(0,new A.dI(r,s))
s.a+="}"}finally{if(0>=$.Y.length)return A.a($.Y,-1)
$.Y.pop()}r=s.a
return r.charCodeAt(0)==0?r:r},
c6:function c6(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
dd:function dd(a){this.a=a
this.b=null},
c7:function c7(a,b,c){var _=this
_.a=a
_.b=b
_.d=_.c=null
_.$ti=c},
h:function h(){},
R:function R(){},
dI:function dI(a,b){this.a=a
this.b=b},
bj:function bj(){},
cc:function cc(){},
jk(a,b,c){var s,r,q,p,o,n=c-b
if(n<=4096)s=$.i8()
else s=new Uint8Array(n)
for(r=a.length,q=0;q<n;++q){p=b+q
if(!(p<r))return A.a(a,p)
o=a[p]
if((o&255)!==o)o=255
s[q]=o}return s},
jj(a,b,c,d){var s=a?$.i7():$.i6()
if(s==null)return null
if(0===c&&d===b.length)return A.hq(s,b)
return A.hq(s,b.subarray(c,d))},
hq(a,b){var s,r
try{s=a.decode(b)
return s}catch(r){}return null},
fU(a,b,c){return new A.bM(a,b)},
jw(a){return a.by()},
j_(a,b){return new A.er(a,[],A.ko())},
j0(a,b,c){var s,r=new A.aQ(""),q=A.j_(r,b)
q.an(a)
s=r.a
return s.charCodeAt(0)==0?s:s},
jl(a){switch(a){case 65:return"Missing extension byte"
case 67:return"Unexpected extension byte"
case 69:return"Invalid UTF-8 byte"
case 71:return"Overlong encoding"
case 73:return"Out of unicode range"
case 75:return"Encoded surrogate"
case 77:return"Unfinished UTF-8 octet sequence"
default:return""}},
eF:function eF(){},
eE:function eE(){},
cD:function cD(){},
cF:function cF(){},
bM:function bM(a,b){this.a=a
this.b=b},
cP:function cP(a,b){this.a=a
this.b=b},
cO:function cO(){},
dF:function dF(a){this.b=a},
es:function es(){},
et:function et(a,b){this.a=a
this.b=b},
er:function er(a,b,c){this.c=a
this.a=b
this.b=c},
e2:function e2(){},
eG:function eG(a){this.b=0
this.c=a},
e1:function e1(a){this.a=a},
eD:function eD(a){this.a=a
this.b=16
this.c=0},
iq(a,b){a=A.y(a,new Error())
if(a==null)a=A.ap(a)
a.stack=b.i(0)
throw a},
aM(a,b,c,d){var s,r=J.iu(a,d)
if(a!==0&&b!=null)for(s=0;s<a;++s)r[s]=b
return r},
ix(a,b,c){var s,r,q=A.f([],c.h("o<0>"))
for(s=a.length,r=0;r<a.length;a.length===s||(0,A.b5)(a),++r)B.a.j(q,c.a(a[r]))
q.$flags=1
return q},
fj(a,b){var s,r
if(Array.isArray(a))return A.f(a.slice(0),b.h("o<0>"))
s=A.f([],b.h("o<0>"))
for(r=J.fc(a);r.n();)B.a.j(s,r.gv())
return s},
fl(a,b,c){var s,r,q,p,o
A.bW(b,"start")
s=c==null
r=!s
if(r){q=c-b
if(q<0)throw A.b(A.a4(c,b,null,"end",null))
if(q===0)return""}if(Array.isArray(a)){p=a
o=p.length
if(s)c=o
return A.h6(b>0||c<o?p.slice(b,c):p)}if(t.Y.b(a))return A.iP(a,b,c)
if(r)a=J.ie(a,c)
if(b>0)a=J.id(a,b)
s=A.fj(a,t.S)
return A.h6(s)},
iP(a,b,c){var s=a.length
if(b>=s)return""
return A.iK(a,b,c==null||c>s?s:c)},
ha(a,b,c){var s=J.fc(b)
if(!s.n())return a
if(c.length===0){do a+=A.p(s.gv())
while(s.n())}else{a+=A.p(s.gv())
while(s.n())a=a+c+A.p(s.gv())}return a},
iN(){return A.S(new Error())},
cG(a,b,c){var s,r,q
for(s=a.length,r=0;r<s;++r){q=a[r]
if(q.b===b)return q}throw A.b(A.av(b,"name","No enum value with that name"))},
cH(a){if(typeof a=="number"||A.dk(a)||a==null)return J.cw(a)
if(typeof a=="string")return JSON.stringify(a)
return A.h5(a)},
ir(a,b){A.dn(a,"error",t.K)
A.dn(b,"stackTrace",t.l)
A.iq(a,b)},
cz(a){return new A.cy(a)},
cx(a,b){return new A.a1(!1,null,b,a)},
av(a,b,c){return new A.a1(!0,a,b,c)},
a4(a,b,c,d,e){return new A.bV(b,c,!0,a,d,"Invalid value")},
bX(a,b,c){if(0>a||a>c)throw A.b(A.a4(a,0,c,"start",null))
if(b!=null){if(a>b||b>c)throw A.b(A.a4(b,a,c,"end",null))
return b}return c},
bW(a,b){if(a<0)throw A.b(A.a4(a,0,null,b,null))
return a},
ff(a,b,c,d){return new A.cI(b,!0,a,d,"Index out of range")},
e0(a){return new A.c2(a)},
hc(a){return new A.d_(a)},
ae(a){return new A.aA(a)},
bC(a){return new A.cE(a)},
a3(a,b,c){return new A.bH(a,b,c)},
it(a,b,c){var s,r
if(A.fI(a)){if(b==="("&&c===")")return"(...)"
return b+"..."+c}s=A.f([],t.s)
B.a.j($.Y,a)
try{A.jT(a,s)}finally{if(0>=$.Y.length)return A.a($.Y,-1)
$.Y.pop()}r=A.ha(b,t.hf.a(s),", ")+c
return r.charCodeAt(0)==0?r:r},
fg(a,b,c){var s,r
if(A.fI(a))return b+"..."+c
s=new A.aQ(b)
B.a.j($.Y,a)
try{r=s
r.a=A.ha(r.a,a,", ")}finally{if(0>=$.Y.length)return A.a($.Y,-1)
$.Y.pop()}s.a+=c
r=s.a
return r.charCodeAt(0)==0?r:r},
jT(a,b){var s,r,q,p,o,n,m,l=a.gE(a),k=0,j=0
for(;;){if(!(k<80||j<3))break
if(!l.n())return
s=A.p(l.gv())
B.a.j(b,s)
k+=s.length+2;++j}if(!l.n()){if(j<=5)return
if(0>=b.length)return A.a(b,-1)
r=b.pop()
if(0>=b.length)return A.a(b,-1)
q=b.pop()}else{p=l.gv();++j
if(!l.n()){if(j<=4){B.a.j(b,A.p(p))
return}r=A.p(p)
if(0>=b.length)return A.a(b,-1)
q=b.pop()
k+=r.length+2}else{o=l.gv();++j
for(;l.n();p=o,o=n){n=l.gv();++j
if(j>100){for(;;){if(!(k>75&&j>3))break
if(0>=b.length)return A.a(b,-1)
k-=b.pop().length+2;--j}B.a.j(b,"...")
return}}q=A.p(p)
r=A.p(o)
k+=r.length+q.length+4}}if(j>b.length+2){k+=5
m="..."}else m=null
for(;;){if(!(k>80&&b.length>3))break
if(0>=b.length)return A.a(b,-1)
k-=b.pop().length+2
if(m==null){k+=5
m="..."}}if(m!=null)B.a.j(b,m)
B.a.j(b,q)
B.a.j(b,r)},
h1(a,b,c,d,e){var s
if(B.i===c){s=B.b.gp(a)
b=J.Q(b)
return A.dV(A.W(A.W($.dt(),s),b))}if(B.i===d){s=B.b.gp(a)
b=J.Q(b)
c=J.Q(c)
return A.dV(A.W(A.W(A.W($.dt(),s),b),c))}if(B.i===e){s=B.b.gp(a)
b=J.Q(b)
c=J.Q(c)
d=J.Q(d)
return A.dV(A.W(A.W(A.W(A.W($.dt(),s),b),c),d))}s=B.b.gp(a)
b=J.Q(b)
c=J.Q(c)
d=J.Q(d)
e=J.Q(e)
e=A.dV(A.W(A.W(A.W(A.W(A.W($.dt(),s),b),c),d),e))
return e},
da:function da(){},
q:function q(){},
cy:function cy(a){this.a=a},
ak:function ak(){},
a1:function a1(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
bV:function bV(a,b,c,d,e,f){var _=this
_.e=a
_.f=b
_.a=c
_.b=d
_.c=e
_.d=f},
cI:function cI(a,b,c,d,e){var _=this
_.f=a
_.a=b
_.b=c
_.c=d
_.d=e},
c2:function c2(a){this.a=a},
d_:function d_(a){this.a=a},
aA:function aA(a){this.a=a},
cE:function cE(a){this.a=a},
bZ:function bZ(){},
ef:function ef(a){this.a=a},
bH:function bH(a,b,c){this.a=a
this.b=b
this.c=c},
e:function e(){},
u:function u(){},
d:function d(){},
dg:function dg(){},
aQ:function aQ(a){this.a=a},
eS(a,b){var s,r,q,p,o,n,m,l,k
if(b+7>a.byteLength)return null
s=a.getUint8(b+1)
if(!(a.getUint8(b)===255&&(s&246)===240))return null
r=(s&1)===1?7:9
q=a.getUint8(b+2)
p=a.getUint8(b+3)
o=a.getUint8(b+4)
n=a.getUint8(b+5)
m=B.b.H(q,2)
l=B.b.H(p,6)
k=((p&3)<<11|o<<3|B.b.H(n,5)&7)>>>0
if(k<r)return null
return new A.e7(k,m&15,(q&1)<<2|l&3,r)},
k6(a,b){var s,r=b+65536,q=a.byteLength
if(r<q)q=r
for(s=b;s+7<=q;++s)if(A.ju(a,s))return s
return-1},
ju(a,b){var s,r,q=A.eS(a,b)
if(q==null)return!1
s=b+q.a
r=a.byteLength
if(s>r)return!1
if(s+7>r)return!0
return A.eS(a,s)!=null},
fd(a){var s=A.cs(a,0),r=a.length,q=0
for(;;){if(!(s>0&&q+s<=r))break
q+=s
s=A.cs(a,q)}if(q>0)for(;;){if(!(q<r&&a[q]===0))break;++q}return q},
e7:function e7(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
du:function du(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=0
_.r=!1
_.w=f
_.x=null},
fH(a,b){return a===255&&(b&224)===224&&(b&24)!==8&&(b&6)===2},
eT(a,b){var s,r,q,p,o,n,m,l,k,j,i,h,g=null,f=a.length
if(b+4>f)return g
s=b+1
if(!(s>=0&&s<f))return A.a(a,s)
r=a[s]
if(!(b>=0&&b<f))return A.a(a,b)
if(!A.fH(a[b],r))return g
s=b+2
if(!(s<f))return A.a(a,s)
q=a[s]
p=r>>>3&3
o=q>>>4&15
n=q>>>2&3
if(n===3)return g
m=p===3
s=m?B.aM:B.aH
if(!(o<s.length))return A.a(s,o)
l=s[o]
if(l===0)return g
A:{if(3===p){if(!(n<3))return A.a(B.L,n)
s=B.L[n]
break A}if(2===p){if(!(n<3))return A.a(B.K,n)
s=B.K[n]
break A}if(!(n<3))return A.a(B.J,n)
s=B.J[n]
break A}k=l*1000
j=q>>>1&1
i=m?B.b.t(144*k,s)+j:B.b.t(72*k,s)+j
if(i<=4)return g
h=b+3
if(!(h<f))return A.a(a,h)
f=(a[h]>>>6&3)===3?1:2
h=m?1152:576
return new A.eu(p,i,s,f,h,(r&1)===0)},
jH(a,b){var s,r,q=a.length
if(b+4>q)return!1
if(!(b<q))return A.a(a,b)
s=a[b]
r=b+1
if(!(r<q))return A.a(a,r)
if(!A.fH(s,a[r]))return!1
s=b+2
if(!(s<q))return A.a(a,s)
s=a[s]
return(s>>>4&15)===0&&(s>>>2&3)!==3},
cs(a,b){var s,r,q,p,o,n,m
if(b<0||b+10>a.length)return 0
s=a.length
if(!(b>=0&&b<s))return A.a(a,b)
r=a[b]
q=b+1
if(!(q<s))return A.a(a,q)
q=a[q]
p=b+2
if(!(p<s))return A.a(a,p)
p=a[p]
if(!(r===73&&q===68&&p===51))return 0
r=b+3
if(!(r<s))return A.a(a,r)
if(a[r]!==255){r=b+4
if(!(r<s))return A.a(a,r)
r=a[r]===255}else r=!0
if(r)return 0
for(o=0,n=6;n<10;++n){r=b+n
if(!(r<s))return A.a(a,r)
r=a[r]
if((r&128)!==0)return 0
o=(o<<7|r)>>>0}r=b+5
if(!(r<s))return A.a(a,r)
m=(a[r]&16)!==0?10:0
return 10+o+m},
dl(a,b){var s,r,q,p=A.cs(a,b)
if(p>0)return p
s=a.length
r=!1
if(b+128===s){if(!(b>=0&&b<s))return A.a(a,b)
if(a[b]===84){q=b+1
if(!(q<s))return A.a(a,q)
if(a[q]===65){r=b+2
if(!(r<s))return A.a(a,r)
r=a[r]===71
s=r}else s=r}else s=r}else s=r
if(s)return 128
return 0},
dm(a,b){var s,r,q,p,o=a.length
if(!(b>=0&&b<o))return A.a(a,b)
s=a[b]
r=b+1
if(!(r<o))return A.a(a,r)
r=a[r]
q=b+2
if(!(q<o))return A.a(a,q)
q=a[q]
p=b+3
if(!(p<o))return A.a(a,p)
return(s<<24|r<<16|q<<8|a[p])>>>0},
hH(a,b,c){var s,r,q=c.length,p=a.length
if(b+q>p)return!1
for(s=0;s<q;++s){r=b+s
if(!(r>=0&&r<p))return A.a(a,r)
if(a[r]!==c.charCodeAt(s))return!1}return!0},
k2(a,b,c){var s,r,q,p,o,n,m
if(c.a===3)s=c.d===1?17:32
else s=c.d===1?9:17
r=c.f?2:0
q=b+4+s+r
for(p=0;p<2;++p){if(!A.hH(a,q,B.aJ[p]))continue
o=q+8
r=a.length
if(o>r)return new A.bP()
n=A.dm(a,q+4)
if((n&1)!==0&&o+4<=r){A.dm(a,o)
o+=4}if((n&2)!==0&&o+4<=r)A.dm(a,o)
return new A.bP()}m=b+36
if(A.hH(a,m,"VBRI")&&m+18<=a.length){A.dm(a,m+14)
A.dm(a,m+10)
return new A.bP()}return null},
iA(a1){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b=A.dl(a1,0),a=a1.length,a0=0
for(;;){if(!(b>0&&a0+b<=a))break
a0+=b
b=A.dl(a1,a0)}s=A.iy(a1,a0)
if(s<0){for(r=a0;r+4<=a;++r)if(A.jH(a1,r))throw A.b(B.ai)
throw A.b(B.at)}q=A.eT(a1,s)
q.toString
p=A.k2(a1,s,q)==null?s:s+q.b
o=t.t
n=A.f([],o)
m=A.f([],o)
l=A.f([],o)
for(o=q.a,k=q.c,j=p,i=0,h=0;j+4<=a;){g=A.dl(a1,j)
if(g>0){j+=g
continue}f=A.eT(a1,j)
if(f!=null&&f.a===o&&f.c===k){e=f.b
d=j+e
if(d>a)break
B.a.j(n,j)
B.a.j(m,e)
B.a.j(l,i)
i+=f.e
j=d
continue}c=A.iz(a1,j+1,q)
if(c<0)break;++h
j=c}if(n.length===0)throw A.b(B.aj)
return new A.dK(A.f([new A.ac(B.v,k,q.d,null)],t.J),a1,new Uint32Array(A.L(n)),new Uint32Array(A.L(m)),new Uint32Array(A.L(l)),k,q.e)},
iy(a,b){var s,r,q
for(s=a.length,r=b;r+4<=s;++r){q=A.dl(a,r)
if(q>0){r+=q-1
continue}if(A.h_(a,r,null))return r}return-1},
iz(a,b,c){var s,r=b+131072,q=a.length
if(r<q)q=r
for(s=b;s+4<=q;++s){if(A.dl(a,s)>0)return s
if(A.h_(a,s,c))return s}return-1},
h_(a,b,c){var s,r,q,p=A.eT(a,b)
if(p==null)return!1
if(c!=null)s=!(p.a===c.a&&p.c===c.c)
else s=!1
if(s)return!1
r=b+p.b
s=a.length
if(r>s)return!1
if(r+4>s)return!0
q=A.eT(a,r)
return q!=null&&q.a===p.a&&q.c===p.c},
eu:function eu(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
bP:function bP(){},
dK:function dK(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.z=0
_.Q=!1},
iD(a){var s,r,q,p,o,n,m,l,k=A.a2(a,0,null),j=A.b1(k,0,k.byteLength),i=j.$ti
j=new A.A(j.a(),i.h("A<1>"))
i=i.c
for(;;){if(!j.n()){s=null
break}r=j.b
s=r==null?i.a(r):r
if(s.a==="moov")break}if(s==null)throw A.b(B.ao)
q=A.K(k,s,"mvhd")
p=1e6
if(q!=null&&q.b<q.c){j=q.b
i=k.getUint8(j)===1?16:8
o=j+4+i
if(o+4<=q.c){n=k.getUint32(o,!1)
p=n>0?n:1e6}}m=A.f([],t.J)
l=A.f([],t.fx)
for(j=A.b1(k,s.b,s.c),i=j.$ti,j=new A.A(j.a(),i.h("A<1>")),i=i.c;j.n();){r=j.b
if(r==null)r=i.a(r)
if(r.a!=="trak")continue
A.iB(k,a,r,m,l,p)}if(m.length===0)throw A.b(B.ah)
if(l.length===0)throw A.b(B.ae)
B.a.bG(l,new A.dN())
return new A.dL(m,a,l)},
iB(b5,b6,b7,b8,b9,c0){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1={},b2=b8.length,b3=A.iC(b5,A.K(b5,b7,"tkhd")),b4=A.K(b5,b7,"mdia")
if(b4==null)return
s=A.K(b5,b4,"mdhd")
b1.a=1e6
if(s!=null){r=s.b
q=b5.getUint8(r)===1?16:8
p=b5.getUint32(r+4+q,!1)
b1.a=p
if(p<=0)b1.a=1e6}o=A.K(b5,b4,"hdlr")
n=o!=null&&A.hB(b5,o.b+8)==="vide"
m=A.K(b5,b4,"minf")
l=m==null?null:A.K(b5,m,"stbl")
if(l==null)return
k=A.K(b5,l,"stsd")
if(k==null)return
j=A.jZ(b5,k,n)
if(j==null)return
i=A.k0(b5,A.K(b5,l,"stsz"))
r=i.length
h=A.k1(b5,A.K(b5,l,"stts"),r)
g=A.jX(b5,A.K(b5,l,"ctts"),r)
f=A.k8(b5,l,i)
e=A.k_(b5,A.K(b5,l,"stss"),r)
d=new A.dM(b1)
c=A.jY(b5,A.K(b5,b7,"edts"),c0)
q=d.$1(c.b)
if(typeof q!=="number")return A.hP(q)
b=c.a-q
for(q=h.length,a=e==null,a0=g.length,a1=f.length,a2=0,a3=0;a3<r;++a3){a4=d.$1(a2)
if(typeof a4!=="number")return a4.bE()
if(!(a3<a0))return A.a(g,a3)
a5=d.$1(a2+g[a3])
if(typeof a5!=="number")return a5.bE()
if(!(a3<a1))return A.a(f,a3)
a6=f[a3]
a7=i[a3]
if(!(a3<q))return A.a(h,a3)
a8=d.$1(a2+h[a3])
a9=d.$1(a2)
if(typeof a8!=="number")return a8.cI()
if(typeof a9!=="number")return A.hP(a9)
b0=a?!0:e.ck(0,a3)
B.a.j(b9,new A.ao(b2,a6,a7,a4+b,a5+b,a8-a9,b0))
a2+=h[a3]}r=j.a
q=j.w
if(r){r=j.b
r.toString
q=new A.aB(r,j.d,j.e,0,1,q,b3)
r=q}else{r=j.c
r.toString
q=new A.ac(r,j.f,j.r,q)
r=q}B.a.j(b8,r)},
iC(a,b){var s,r,q,p,o,n,m
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
b1(a,b,c){return new A.br(A.ki(a,b,c),t.g6)},
ki(a,b,c){return function(){var s=a,r=b,q=c
var p=0,o=2,n=[],m,l,k,j,i,h,g,f
return function $async$b1(d,e,a0){if(e===1){n.push(a0)
p=o}for(;;)switch(p){case 0:m=r
case 3:if(!(l=m+8,l<=q)){p=5
break}k=s.getUint32(m,!1)
j=A.hB(s,m+4)
if(k===1){if(m+16>q){p=1
break}i=s.getUint32(l,!1)
h=s.getUint32(m+12,!1)
k=(B.b.ah(i,32)|h)>>>0
g=16}else{if(k===0)k=q-m
g=8}if(k<g||m+k>q){p=1
break}f=m+k
p=6
return d.b=new A.d4(j,m+g,f),1
case 6:case 4:m=f
p=3
break
case 5:case 1:return 0
case 2:return d.c=n.at(-1),3}}}},
K(a,b,c){var s,r,q
for(s=A.b1(a,b.b,b.c),r=s.$ti,s=new A.A(s.a(),r.h("A<1>")),r=r.c;s.n();){q=s.b
if(q==null)q=r.a(q)
if(q.a===c)return q}return null},
hB(a,b){var s,r=A.f([],t.t)
for(s=0;s<4;++s)r.push(a.getUint8(b+s))
return A.fl(r,0,null)},
hd(a,b,c,d){return new A.d6(!1,null,a,0,0,b,c,d)},
jZ(a2,a3,a4){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b=null,a=A.b1(a2,a3.b+8,a3.c),a0=a.$ti,a1=new A.A(a.a(),a0.h("A<1>"))
if(a1.n()){a=a1.b
s=a==null?a0.c.a(a):a}else s=b
if(s==null)return b
r=s.a
if(a4){a=s.b
q=a2.getUint16(a+24,!1)
p=a2.getUint16(a+26,!1)
a=A.b1(a2,a+78,s.c)
a0=a.$ti
a=new A.A(a.a(),a0.h("A<1>"))
a0=a0.c
for(;;){if(!a.n()){o=b
break}n=a.b
if(n==null)n=a0.a(n)
m=n.a
if(m==="avcC"||m==="hvcC"||m==="av1C"){a=n.b
n=n.c
o=A.cZ(J.fb(B.j.gI(a2),a2.byteOffset),a,n)
break}}switch(r){case"avc1":case"avc3":l=B.S
break
case"hev1":case"hvc1":l=B.T
break
case"av01":l=B.U
break
default:return b}return new A.d6(!0,l,b,q,p,0,0,o==null?b:new A.ag(l,b,o))}a=s.b
k=a2.getUint16(a+16,!1)
j=a2.getUint32(a+24,!1)>>>16
i=a+28
if(r==="mp4a"){a=A.b1(a2,i,s.c)
a0=a.$ti
a=new A.A(a.a(),a0.h("A<1>"))
a0=a0.c
for(;;){if(!a.n()){h=b
break}n=a.b
if(n==null)n=a0.a(n)
if(n.a==="esds"){h=A.jq(a2,n)
break}}if(j!==0)a=j
else a=h==null?0:A.jr(h)
return A.hd(B.f,a,k,h==null?b:new A.ag(b,B.f,h))}if(r==="Opus"){a=A.b1(a2,i,s.c)
a0=a.$ti
a=new A.A(a.a(),a0.h("A<1>"))
a0=a0.c
for(;;){if(!a.n()){g=b
break}n=a.b
if(n==null)n=a0.a(n)
if(n.a==="dOps"){f=new Uint8Array(19)
B.c.P(f,0,8,new A.cC("OpusHead"))
f[8]=1
a=n.b
e=a2.getUint8(a+1)
f[9]=e===0?k:e
d=a2.getUint16(a+2,!1)
c=A.a2(f,0,b)
c.$flags&2&&A.z(c,10)
c.setUint16(10,d,!0)
c.setUint32(12,j===0?48e3:j,!0)
g=f
break}}a=j===0?48e3:j
return A.hd(B.h,a,k,g==null?b:new A.ag(b,B.h,g))}return b},
jr(a){var s,r,q,p={}
p.a=0
p=new A.eN(p,a)
s=p.$1(5)
if((s===31?p.$1(6):s)<0)return 0
r=p.$1(4)
if(r<0)return 0
if(r===15){q=p.$1(24)
return q<0?0:q}return r<13?B.aO[r]:0},
jq(a,b){var s,r,q,p,o,n,m=A.fw(a,b.b+4,b.c)
if(m==null||m.a!==3)return null
s=m.b+3
for(r=m.c;s<r;){q=A.fw(a,s,r)
if(q==null)break
if(q.a===4){p=q.b+13
for(o=q.c;p<o;){n=A.fw(a,p,o)
if(n==null)break
if(n.a===5){r=n.b
o=n.c
return A.cZ(J.fb(B.j.gI(a),a.byteOffset),r,o)}p=n.d}}s=q.d}return null},
fw(a,b,c){var s,r,q,p,o,n,m=b+1
if(m>c)return null
s=a.getUint8(b)
for(r=0,q=0;q<4;++q,m=p){if(m>=c)return null
p=m+1
o=a.getUint8(m)
r=(r<<7|o&127)>>>0
if((o&128)===0){m=p
break}}n=m+r
if(n>c)return null
return new A.ee(s,m,n,n)},
k0(a,b){var s,r,q,p,o
if(b==null)return B.O
s=b.b+4
r=a.getUint32(s,!1)
q=a.getUint32(s+4,!1)
s+=8
if(r!==0)return A.aM(q,r,!1,t.S)
p=A.aM(q,0,!1,t.S)
for(o=0;o<q;++o)B.a.q(p,o,a.getUint32(s+o*4,!1))
return p},
k1(a,b,c){var s,r,q,p,o,n,m,l,k=A.aM(c,0,!1,t.S)
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
B.a.q(k,q,n);++m
q=l}++p}return k},
jX(a,b,c){var s,r,q,p,o,n,m,l,k,j,i,h=A.aM(c,0,!1,t.S)
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
B.a.q(h,o,k);++j
o=i}++n}return h},
jY(a,b,c){var s,r,q,p,o,n,m,l,k,j,i,h,g,f
if(b==null||c<=0)return B.W
s=A.K(a,b,"elst")
if(s==null||s.b+8>s.c)return B.W
r=s.b
q=a.getUint8(r)===1
p=q?20:12
o=r+4
n=a.getUint32(o,!1)
o+=4
for(r=s.c,m=0,l=0,k=!1,j=0;j<n;++j,o=i){i=o+p
if(i>r)break
h=o+4
if(q){g=(B.b.ah(a.getUint32(o,!1),32)|a.getUint32(h,!1))>>>0
h=o+8
f=a.getInt32(h,!1)*4294967296+a.getUint32(h+4,!1)}else{g=a.getUint32(o,!1)
f=a.getInt32(h,!1)}if(f<0){if(!k)m+=g
continue}if(!k){l=f
k=!0}}return new A.d9(B.b.t(m*1e6,c),l)},
k_(a,b,c){var s,r,q,p
if(b==null)return null
s=b.b+4
r=a.getUint32(s,!1)
s+=4
q=A.iw(t.S)
for(p=0;p<r;++p){q.j(0,a.getUint32(s,!1)-1)
s+=4}return q},
k8(a0,a1,a2){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d=A.jW(a0,a1),c=A.K(a0,a1,"stsc"),b=a2.length,a=A.aM(b,0,!1,t.S)
if(d.length===0||c==null)return a
s=c.b+4
r=a0.getUint32(s,!1)
s+=4
q=t.t
p=A.f([],q)
o=A.f([],q)
for(n=0;n<r;++n){B.a.j(p,a0.getUint32(s,!1))
B.a.j(o,a0.getUint32(s+4,!1))
s+=12}m=0
n=0
l=1
k=0
for(;;){q=d.length
if(!(k<q&&m<b))break
j=o.length
i=p.length
h=k+1
for(;;){if(n<i){if(!(n>=0))return A.a(p,n)
g=p[n]<=h}else g=!1
if(!g)break
if(!(n>=0&&n<j))return A.a(o,n)
l=o[n];++n}if(!(k<q))return A.a(d,k)
f=d[k]
e=0
for(;;){if(!(e<l&&m<b))break
B.a.q(a,m,f)
if(!(m>=0&&m<b))return A.a(a2,m)
f+=a2[m];++m;++e}k=h}return a},
jW(a,b){var s,r,q,p,o,n,m=A.K(a,b,"stco")
if(m!=null){s=m.b+4
r=a.getUint32(s,!1)
s+=4
q=A.f([],t.t)
for(p=0;p<r;++p)q.push(a.getUint32(s+p*4,!1))
return q}o=A.K(a,b,"co64")
if(o!=null){s=o.b+4
r=a.getUint32(s,!1)
s+=4
q=A.f([],t.t)
for(p=0;p<r;++p){n=s+p*8
q.push((B.b.ah(a.getUint32(n,!1),32)|a.getUint32(n+4,!1))>>>0)}return q}return B.O},
d4:function d4(a,b,c){this.a=a
this.b=b
this.c=c},
ao:function ao(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g},
dL:function dL(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.d=0
_.e=!1},
dN:function dN(){},
dM:function dM(a){this.a=a},
dO:function dO(){},
d6:function d6(a,b,c,d,e,f,g,h){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.w=h},
eN:function eN(a,b){this.a=a
this.b=b},
ee:function ee(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
d9:function d9(a,b){this.a=a
this.b=b},
hL(a,b){var s
if(a.length<8)return!1
for(s=0;s<8;++s)if(a[s]!==b[s])return!1
return!0},
iG(b1){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0=A.a2(b1,0,null)
if(b0.byteLength<27||!A.hI(b0,0))throw A.b(B.ad)
s=A.f([],t.r)
r=new A.d7($.by())
for(q=-1,p=0;o=p+27,o<=b0.byteLength;p=l){if(!A.hI(b0,p))throw A.b(B.aq)
n=b0.getUint8(p+26)
m=o+n
if(m>b0.byteLength)throw A.b(B.an)
for(l=m,k=0;k<n;++k,l=i){j=b0.getUint8(o+k)
i=l+j
if(i>b0.byteLength)throw A.b(B.as)
r.j(0,J.cu(B.j.gI(b0),b0.byteOffset+l,j))
if(j<255){B.a.j(s,r.cB())
r.N(0)}}h=b0.getUint32(p+6,!0)
g=b0.getUint32(p+10,!0)
if(!(h===4294967295&&g===4294967295))q=(B.b.ah(g,32)|h)>>>0}if(s.length===0||!A.hL(B.a.gbr(s),B.M))throw A.b(B.ab)
f=B.a.gbr(s)
if(f.length>=19){e=f[9]
d=(f[12]|f[13]<<8|f[14]<<16|f[15]<<24)>>>0
if(d<=0)d=48e3}else{d=48e3
e=2}c=B.a.bH(s,s.length>1&&A.hL(s[1],B.aN)?2:1)
b=A.kI(f)
o=c.length
a=t.S
a0=A.aM(o,0,!1,a)
a1=c.length
a2=A.aM(a1,0,!1,a)
for(a3=0,k=0;k<c.length;++k){a4=A.kJ(c[k])
B.a.q(a2,k,a4>0?a4:960)
a5=a3-b
B.a.q(a0,k,a5>0?a5:0)
if(!(k<a1))return A.a(a2,k)
a3+=a2[k]}a6=(q>b?q:a3)-b
for(a=a6>0,k=0;a7=c.length,k<a7;k=a8){a8=k+1
if(a8<a7){if(!(a8<o))return A.a(a0,a8)
a9=a0[a8]}else a9=a?a6:0
if(!(k<o))return A.a(a0,k)
a4=a9-a0[k]
if(a4<0)a7=0
else{if(!(k<a1))return A.a(a2,k)
a7=a2[k]
a7=a4>a7?a7:a4}B.a.q(a2,k,a7)}o=A.f([new A.ac(B.h,d,e,new A.ag(null,B.h,f))],t.J)
return new A.dQ(o,c,a0,a2,a6<0?0:a6)},
hI(a,b){var s
if(b+4>a.byteLength)return!1
for(s=0;s<4;++s)if(a.getUint8(b+s)!==B.aG[s])return!1
return!0},
dQ:function dQ(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=0
_.r=!1},
bt(a){var s
switch(a.a){case 0:s=1
break
case 1:s=2
break
case 2:s=3
break
case 3:s=4
break
default:s=null}return s},
iR(a){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c="wav",b=A.a2(a,0,null)
if(b.byteLength<12||!A.hA(b,0,"RIFF")||!A.hA(b,8,"WAVE"))throw A.b(B.ar)
for(s=-1,r=0,q=-1,p=0,o=12;n=o+8,n<=b.byteLength;o=j){m=A.k3(b,o)
l=b.getUint32(o+4,!0)
if(m==="fmt "){r=l
s=n}else if(m==="data"){k=b.byteLength
p=n+l>k?k-n:l
if(l===0){p=k-n
q=n
break}q=n}j=(n+l+1&4294967294)>>>0
if(j<=o)break}if(s<0||r<16)throw A.b(B.ap)
if(q<0)throw A.b(B.al)
i=b.getUint16(s,!0)
h=b.getUint16(s+2,!0)
g=b.getUint32(s+4,!0)
f=b.getUint16(s+14,!0)
if(i===65534){if(r<40||s+40>b.byteLength)throw A.b(B.ak)
e=b.getUint16(s+18,!0)
k=s+24
if(!A.jO(b,k))throw A.b(B.ac)
i=b.getUint16(k,!0)}else e=f
k=i===1
if(!k&&i!==3)throw A.b(A.dx(c,"unsupported WAVE format tag "+i))
if(e===0)e=f
if(e!==f)throw A.b(A.dx(c,"valid bits "+e+" != container "+f))
if(k&&f===8)d=B.X
else if(k&&f===16)d=B.Y
else if(k&&f===24)d=B.Z
else{if(!(i===3&&f===32))throw A.b(A.dx(c,"unsupported PCM: fmt="+i+" bits="+f))
d=B.a_}A:{if(B.X===d||B.Y===d){k=B.w
break A}if(B.Z===d||B.a_===d){k=B.x
break A}k=null}if(h<1||h>8||g<1)throw A.b(A.dx(c,"bad ch="+h+" sr="+g))
return new A.e3(b,q,p,g,h,d,A.f([new A.ac(k,g,h,null)],t.J))},
jO(a,b){var s,r
if(b+16>a.byteLength)return!1
for(s=b+2,r=0;r<14;++r)if(a.getUint8(s+r)!==B.aK[r])return!1
return!0},
hA(a,b,c){var s,r,q
if(b+4>a.byteLength)return!1
for(s=c.length,r=0;r<4;++r){q=a.getUint8(b+r)
if(!(r<s))return A.a(c,r)
if(q!==c.charCodeAt(r))return!1}return!0},
k3(a,b){var s,r=A.f([],t.t)
for(s=0;s<4;++s)r.push(a.getUint8(b+s))
return A.fl(r,0,null)},
aZ:function aZ(a,b){this.a=a
this.b=b},
e3:function e3(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.w=0
_.x=!1},
dq(a){return A.kq(a)},
kq(a){var s=0,r=A.G(t.H),q=1,p=[],o,n,m,l
var $async$dq=A.H(function(b,c){if(b===1){p.push(c)
s=q}for(;;)switch(s){case 0:n={}
m=a.r
m.toString
t.eE.a(m)
n.a=null
a.cr(new A.eY(n,m))
s=2
return A.cn(a.c.a,$async$dq)
case 2:q=4
n=n.a
n=n==null?null:n.u()
s=7
return A.cn(n instanceof A.j?n:A.fn(n,t.H),$async$dq)
case 7:q=1
s=6
break
case 4:q=3
l=p.pop()
s=6
break
case 3:s=1
break
case 6:return A.E(null,r)
case 1:return A.D(p.at(-1),r)}})
return A.F($async$dq,r)},
kG(){A.kK()
A.kM(A.kt())
return null},
eY:function eY(a,b){this.a=a
this.b=b},
X:function X(a,b){this.a=a
this.b=b},
Z:function Z(a,b){this.a=a
this.b=b},
I:function I(a,b){this.a=a
this.b=b},
aj:function aj(){},
aB:function aB(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g},
ac:function ac(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
kK(){var s=$.fM()
s.bw(3329,A.ks())
s.bw(3330,A.kr())},
iQ(a){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=null,b="demux protocol: truncated message (wanted 4 bytes at "
t.p.a(a)
s=A.a2(a,0,c)
r=new A.de(a,s)
q=r.O()===1?r.Z():c
p=r.O()
o=r.bA()
n=A.f([],t.J)
for(m=t.q,l=t.G,k=0;k<o;++k){j=r.c
i=j+1
h=a.byteLength
if(i>h)A.n(A.a3("demux protocol: truncated message (wanted 1 bytes at "+j+" of "+h+")",c,c))
r.c=i
switch(s.getUint8(j)){case 0:j=A.cG(B.P,r.ar(),l)
i=r.c
h=a.byteLength
if(i+4>h)A.n(A.a3(b+i+" of "+h+")",c,c))
g=s.getUint32(i,!0)
i=r.c+=4
h=a.byteLength
if(i+4>h)A.n(A.a3(b+i+" of "+h+")",c,c))
f=s.getUint32(i,!0)
i=r.c+=4
h=a.byteLength
if(i+4>h)A.n(A.a3(b+i+" of "+h+")",c,c))
e=s.getUint32(i,!0)
i=r.c+=4
h=a.byteLength
if(i+4>h)A.n(A.a3(b+i+" of "+h+")",c,c))
d=s.getUint32(i,!0)
r.c+=4
i=r.Z()
B.a.j(n,new A.aB(j,g,f,e,d,r.bp(),i))
break
case 1:j=A.cG(B.Q,r.ar(),m)
i=r.c
h=a.byteLength
if(i+4>h)A.n(A.a3(b+i+" of "+h+")",c,c))
g=s.getUint32(i,!0)
i=r.c+=4
h=a.byteLength
if(i+4>h)A.n(A.a3(b+i+" of "+h+")",c,c))
f=s.getUint32(i,!0)
r.c+=4
B.a.j(n,new A.ac(j,g,f,r.bp()))
break
default:throw A.b(B.az)}}return new A.aR(n,q,p===1)},
iH(a){var s,r,q,p,o,n
t.p.a(a)
s=new A.de(a,A.a2(a,0,null))
r=s.Z()
q=s.Z()
p=s.Z()
o=s.O()
n=s.al()
return new A.aP(new A.ah(s.bl(),r,q,p,o===1,n))},
hs(){var s=A.f([],t.r)
return new A.eL(new A.d5(s),new Uint8Array(8))},
aR:function aR(a,b,c){this.a=a
this.b=b
this.c=c},
aP:function aP(a){this.a=a},
eL:function eL(a,b){this.a=a
this.b=b
this.c=$},
de:function de(a,b){this.a=a
this.b=b
this.c=0},
dx(a,b){return new A.w(a,b)},
dJ:function dJ(){},
w:function w(a,b){this.b=a
this.a=b},
aG:function aG(a,b){this.b=a
this.a=b},
ah:function ah(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
ag:function ag(a,b,c){this.a=a
this.b=b
this.c=c},
kM(a){var s,r,q={}
q.a=null
s=A.b_(v.G.self)
q=new A.f9(q,a)
if(typeof q=="function")A.n(A.cx("Attempting to rewrap a JS function.",null))
r=function(b,c){return function(d){return b(c,d,arguments.length)}}(A.jt,q)
r[$.fL()]=q
s.onmessage=r},
jv(a){var s,r,q,p,o,n,m,l,k,j,i,h=null
if(a==null||!t.m.b(a))return h
A.b_(a)
s=t.dE.a(a.h)
if(s==null)return h
r=null
try{q=s
p=q.byteLength
if(p<12)A.n(A.a3("spawn envelope: need at least 12 bytes, got "+p,h,h))
o=A.a2(q,0,12)
n=o.getUint8(0)
if(n!==1)A.n(A.a3("spawn envelope: unsupported version "+n+" (expected 1)",h,h))
m=o.getUint8(1)
l=A.iS(m)
if(l==null)A.n(A.a3("spawn envelope: unknown kind "+m,h,h))
r=new A.d1(n,l,o.getUint16(2,!0),o.getUint32(4,!0),o.getUint32(8,!0))}catch(k){if(A.P(k) instanceof A.bH)return h
else throw k}j=a.p
if(j==null)i=h
else i=r.c!==0||r.b===B.t||r.b===B.u||r.b===B.k?t.Y.a(j):A.ft(j)
return new A.T(r.b,r.c,r.d,i,h)},
kf(a,b){var s,r,q=t.c.a(new v.G.Array()),p=new A.eW(A.f([],t.f),q)
for(s=b.length,r=0;r<b.length;b.length===s||(0,A.b5)(b),++r)p.$1(b[r])
return q},
fA(a,b){var s,r,q,p,o
if(a==null)return null
if(a instanceof A.bT){s={}
r=a.a
s.$spawn$platform=r
if(r!=null&&A.hy(r)!=="SharedArrayBuffer")B.a.j(b,r)
return s}if(A.dk(a))return a
if(A.co(a))return a
if(typeof a=="number")return a
if(typeof a=="string")return a
if(t.x.b(a))return t.u.a(a)
if(t.p.b(a))return a
if(t.U.b(a))return a
if(t.go.b(a))return a
if(t.dQ.b(a))return a
if(t.h7.b(a))return a
if(t.an.b(a))return a
if(t.bv.b(a))return a
if(t.h4.b(a))return a
if(t.gN.b(a))return a
if(t.W.b(a))return a
if(t.j.b(a)){q=t.c.a(new v.G.Array())
for(p=0;o=J.cr(a),p<o.gk(a);++p)q[p]=A.fA(o.m(a,p),b)
return q}if(a instanceof A.R){s={}
a.Y(0,new A.eV(s,b))
return s}throw A.b(A.av(a,"message","spawn cannot carry this value"))},
ft(a){var s,r,q,p
if(a==null)return null
if(typeof a==="boolean")return A.hu(a)
if(typeof a==="string")return A.aq(a)
if(typeof a==="number"){A.dj(a)
if(isFinite(a))s=a===(a<0?Math.ceil(a):Math.floor(a))
else s=!1
if(s)return B.I.cC(a)
return a}if(!(typeof a==="object"))return null
switch(A.hy(a)){case"ArrayBuffer":return t.u.a(a)
case"Uint8Array":return t.Y.a(a)
case"Int8Array":return t.cv.a(a)
case"Uint8ClampedArray":return t.gi.a(a)
case"Int16Array":return t.at.a(a)
case"Uint16Array":return t.d.a(a)
case"Int32Array":return t.ha.a(a)
case"Uint32Array":return t.dk.a(a)
case"Float32Array":return t.E.a(a)
case"Float64Array":return t.c2.a(a)
case"DataView":return t.A.a(a)
case"Array":t.c.a(a)
r=A.aa(A.dj(a.length))
s=[]
for(q=0;q<r;++q)s.push(A.ft(a[q]))
return s
default:A.b_(a)
if("$spawn$platform" in a)return new A.bT(a.$spawn$platform)
p=t.c.a(v.G.Object.keys(a))
r=A.aa(A.dj(p.length))
s=A.fX(t.N,t.X)
for(q=0;q<r;++q)s.q(0,A.aq(p[q]),A.ft(a[A.aq(p[q])]))
return s}},
hy(a){var s,r=A.hv(A.b_(a).constructor)
if(r==null)s=null
else{s=A.eM(r.name)
if(s==null)s=null}return s},
f9:function f9(a,b){this.a=a
this.b=b},
f8:function f8(){},
di:function di(a,b){this.a=a
this.b=b},
eW:function eW(a,b){this.a=a
this.b=b},
eV:function eV(a,b){this.a=a
this.b=b},
cT:function cT(a,b){this.a=a
this.b=b},
cU:function cU(a,b){this.a=a
this.b=b},
dS:function dS(){},
ds(a,b,c,d){return A.kL(a,b,c,d)},
kL(a,b,c,a0){var s=0,r=A.G(t.H),q=1,p=[],o=[],n,m,l,k,j,i,h,g,f,e,d
var $async$ds=A.H(function(a1,a2){if(a1===1){p.push(a2)
s=q}for(;;)switch(s){case 0:f=t.X
e=new A.cm(a,A.h9(f),new A.bl(new A.j($.i,t.D),t.h),A.f([],t.b4),c)
a.M(new A.T(B.t,0,0,B.e.J(B.a9.cn(A.fY(["v",1,"caps",a0.by()],t.N,f),null)),null))
f=a.a
n=new A.bn(f,A.B(f).h("bn<1>")).ct(e.gc0(),e.gc2())
q=3
f=b.$1(e)
s=6
return A.cn(f instanceof A.j?f:A.fn(f,t.H),$async$ds)
case 6:o.push(5)
s=4
break
case 3:q=2
d=p.pop()
m=A.P(d)
l=A.S(d)
f=A.ap(m)
j=t.l.a(l)
i=e.a
h=J.at(f)
g=A.M(h.gl(f).a,null)
f=h.i(f)
j=j.i(0)
i.M(new A.T(B.k,0,0,B.e.J(g+"\n"+A.fK(f,"\n"," ")+"\n"+j),null))
o.push(5)
s=4
break
case 2:o=[1]
case 4:q=1
e.aF()
f=n
if(((f.e&=4294967279)&8)===0)f.aZ()
f=f.f
s=7
return A.cn(f==null?$.fa():f,$async$ds)
case 7:a.M(B.aA)
s=o.pop()
break
case 5:return A.E(null,r)
case 1:return A.D(p.at(-1),r)}})
return A.F($async$ds,r)},
cm:function cm(a,b,c,d,e){var _=this
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
T:function T(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
kv(a){var s
if(t.bG.b(a)){s=a.gbz()
if(s<1||s>65535)throw A.b(A.av(s,"typeId",A.fF(a).i(0)+".typeId must be in 1..65535 (0 is reserved)"))
return new A.bq(s,a.bo())}A.fs(a,A.f([],t.f),"message")
return new A.bq(0,a)},
fD(a,b){var s
if(a===0)return b
if(!t.p.b(b))throw A.b(A.ae("spawn: frame declares typeId "+a+" but carries "+J.bz(b).i(0)+" instead of bytes"))
s=$.fM().a.m(0,a)
if(s==null)A.n(A.ae("spawn: no WireMessage decoder registered for typeId "+a+". Both ends must call the same WireRegistry.instance.register(...)."))
return s.$1(b)},
fs(a,b,c){var s,r,q,p
if(a==null||A.dk(a)||typeof a=="number"||typeof a=="string"||t.ak.b(a)||t.x.b(a)||a instanceof A.bT)return
s=t.j.b(a)
if(s||a instanceof A.R){for(r=b.length,q=0;q<r;++q)if(b[q]===a)throw A.b(A.av(a,c,"spawn cannot carry a cyclic structure"))
B.a.j(b,a)
if(s)for(s=c+"[",p=0;r=J.cr(a),p<r.gk(a);++p)A.fs(r.m(a,p),b,s+p+"]")
else if(a instanceof A.R)a.Y(0,new A.eQ(c,b))
if(0>=b.length)return A.a(b,-1)
b.pop()
return}throw A.b(A.av(a,c,"spawn cannot carry "+J.bz(a).i(0)+". Wrap a platform object (VideoFrame, AudioData, ImageBitmap, ...) in a PlatformValue. Portable values are null, bool, int, double, String, TypedData, ByteBuffer, and List/Map<String, ...> of those. Implement WireMessage for anything else."))},
eQ:function eQ(a,b){this.a=a
this.b=b},
bT:function bT(a){this.a=a},
iS(a){var s,r
for(s=0;s<6;++s){r=B.aF[s]
if(r.c===a)return r}return null},
af:function af(a,b,c){this.c=a
this.a=b
this.b=c},
d1:function d1(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
e4:function e4(a){this.a=a},
a2(a,b,c){var s=a.BYTES_PER_ELEMENT
c=A.bX(b,c,B.b.t(a.byteLength,s))
return J.ib(B.c.gI(a),a.byteOffset+b*s,(c-b)*s)},
cZ(a,b,c){var s=a.BYTES_PER_ELEMENT
c=A.bX(b,c,B.b.t(a.byteLength,s))
return J.cu(B.c.gI(a),a.byteOffset+b*s,(c-b)*s)},
hU(a){return v.mangledGlobalNames[a]},
jt(a,b,c){t.Z.a(a)
if(A.aa(c)>=1)return a.$1(b)
return a.$0()},
io(a,b){var s,r,q,p,o,n,m
switch(b==null?A.ip(a):b){case B.q:return A.iR(a)
case B.p:return A.iG(a)
case B.o:s=A.a2(a,0,null)
r=A.fd(a)
q=A.eS(s,r)
if(q==null)A.n(B.am)
p=q.b
if(!(p<16))return A.a(B.N,p)
o=B.N[p]
if(o!==0){n=q.c
n=(n===7?8:n)<1}else n=!0
if(n)A.n(B.af)
n=q.c
m=new Uint8Array(2)
m[0]=p>>>1&7|16
m[1]=(p&1)<<7|(n&15)<<3
p=n===7?8:n
return new A.du(A.f([new A.ac(B.f,o,p,new A.ag(null,B.f,m))],t.J),a,s,o,r,q.a)
case B.l:return A.iA(a)
case B.n:case B.H:return A.iD(a)
default:return null}},
ip(a){var s,r,q,p,o,n=a.length
if(n>=12&&a[0]===82&&a[1]===73&&a[2]===70&&a[3]===70&&a[8]===87&&a[9]===65&&a[10]===86&&a[11]===69)return B.q
if(n>=4&&a[0]===79&&a[1]===103&&a[2]===103&&a[3]===83)return B.p
if(n>=8&&a[4]===102&&a[5]===116&&a[6]===121&&a[7]===112)return B.n
s=A.cs(a,0)
r=0
for(;;){if(!(s>0&&r+s<=n))break
r+=s
s=A.cs(a,r)}q=r>0
if(q)for(;;){if(!(r<n&&a[r]===0))break;++r}if(r+2<=n){if(!(r>=0&&r<n))return A.a(a,r)
p=a[r]
o=r+1
if(!(o<n))return A.a(a,o)
o=a[o]
if(p===255&&(o&246)===240)return B.o
if(A.fH(p,o))return B.l}if(q)return B.l
return null},
kI(a){var s
if(a.length<12)return 0
for(s=0;s<8;++s)if(a[s]!==B.M[s])return 0
return(a[10]|a[11]<<8)>>>0},
kJ(a){var s,r,q,p,o=a.length
if(o===0)return 0
if(0>=o)return A.a(a,0)
s=a[0]
r=B.aI[s>>>3&31]
switch(s&3){case 0:q=1
break
case 1:case 2:q=2
break
default:if(o<2)return 0
q=a[1]&63}if(q<1||q>48)return 0
p=r*q
return p>5760?0:p}},B={}
var w=[A,J,B]
var $={}
A.fh.prototype={}
J.cJ.prototype={
K(a,b){return a===b},
gp(a){return A.bU(a)},
i(a){return"Instance of '"+A.cR(a)+"'"},
gl(a){return A.ab(A.fu(this))}}
J.cL.prototype={
i(a){return String(a)},
gp(a){return a?519018:218159},
gl(a){return A.ab(t.y)},
$il:1,
$ib2:1}
J.bJ.prototype={
K(a,b){return null==b},
i(a){return"null"},
gp(a){return 0},
gl(a){return A.ab(t.P)},
$il:1,
$iu:1}
J.bL.prototype={$ir:1}
J.ax.prototype={
gp(a){return 0},
gl(a){return B.aW},
i(a){return String(a)}}
J.cQ.prototype={}
J.c1.prototype={}
J.ai.prototype={
i(a){var s=a[$.hW()]
if(s==null)s=a[$.fL()]
if(s==null)return this.bI(a)
return"JavaScript function for "+J.cw(s)},
$iaI:1}
J.b8.prototype={
gp(a){return 0},
i(a){return String(a)}}
J.b9.prototype={
gp(a){return 0},
i(a){return String(a)}}
J.o.prototype={
j(a,b){A.a9(a).c.a(b)
a.$flags&1&&A.z(a,29)
a.push(b)},
N(a){a.$flags&1&&A.z(a,"clear","clear")
a.length=0},
bx(a,b){return A.cX(a,0,A.dn(b,"count",t.S),A.a9(a).c)},
ap(a,b){return A.cX(a,b,null,A.a9(a).c)},
X(a,b){if(!(b>=0&&b<a.length))return A.a(a,b)
return a[b]},
bH(a,b){var s=a.length
if(b>s)throw A.b(A.a4(b,0,s,"start",null))
if(b===s)return A.f([],A.a9(a))
return A.f(a.slice(b,s),A.a9(a))},
gbr(a){if(a.length>0)return a[0]
throw A.b(A.fT())},
cf(a,b){var s,r
A.a9(a).h("b2(1)").a(b)
s=a.length
for(r=0;r<s;++r){if(b.$1(a[r]))return!0
if(a.length!==s)throw A.b(A.bC(a))}return!1},
bG(a,b){var s,r,q,p,o,n=A.a9(a)
n.h("c(1,1)?").a(b)
a.$flags&2&&A.z(a,"sort")
s=a.length
if(s<2)return
if(s===2){r=a[0]
q=a[1]
n=b.$2(r,q)
if(typeof n!=="number")return n.cH()
if(n>0){a[0]=q
a[1]=r}return}p=0
if(n.c.b(null))for(o=0;o<a.length;++o)if(a[o]===void 0){a[o]=null;++p}a.sort(A.dp(b,2))
if(p>0)this.c6(a,p)},
c6(a,b){var s,r=a.length
for(;s=r-1,r>0;r=s)if(a[s]===null){a[s]=void 0;--b
if(b===0)break}},
gbt(a){return a.length!==0},
i(a){return A.fg(a,"[","]")},
gE(a){return new J.bA(a,a.length,A.a9(a).h("bA<1>"))},
gp(a){return A.bU(a)},
gk(a){return a.length},
m(a,b){if(!(b>=0&&b<a.length))throw A.b(A.eZ(a,b))
return a[b]},
q(a,b,c){A.a9(a).c.a(c)
a.$flags&2&&A.z(a)
if(!(b>=0&&b<a.length))throw A.b(A.eZ(a,b))
a[b]=c},
gl(a){return A.ab(A.a9(a))},
$ie:1,
$ik:1}
J.cK.prototype={
cD(a){var s,r,q
if(!Array.isArray(a))return null
s=a.$flags|0
if((s&4)!==0)r="const, "
else if((s&2)!==0)r="unmodifiable, "
else r=(s&1)!==0?"fixed, ":""
q="Instance of '"+A.cR(a)+"'"
if(r==="")return q
return q+" ("+r+"length: "+a.length+")"}}
J.dE.prototype={}
J.bA.prototype={
gv(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s,r=this,q=r.a,p=q.length
if(r.b!==p){q=A.b5(q)
throw A.b(q)}s=r.c
if(s>=p){r.d=null
return!1}r.d=q[s]
r.c=s+1
return!0},
$iad:1}
J.bK.prototype={
aK(a,b){var s
A.hw(b)
if(a<b)return-1
else if(a>b)return 1
else if(a===b){if(a===0){s=this.gaN(b)
if(this.gaN(a)===s)return 0
if(this.gaN(a))return-1
return 1}return 0}else if(isNaN(a)){if(isNaN(b))return 0
return 1}else return-1},
gaN(a){return a===0?1/a<0:a<0},
cC(a){var s
if(a>=-2147483648&&a<=2147483647)return a|0
if(isFinite(a)){s=a<0?Math.ceil(a):Math.floor(a)
return s+0}throw A.b(A.e0(""+a+".toInt()"))},
ci(a,b,c){if(B.b.aK(b,c)>0)throw A.b(A.bw(b))
if(this.aK(a,b)<0)return b
if(this.aK(a,c)>0)return c
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
aS(a,b){var s=a%b
if(s===0)return 0
if(s>0)return s
return s+b},
t(a,b){if((a|0)===a)if(b>=1||b<-1)return a/b|0
return this.bg(a,b)},
F(a,b){return(a|0)===a?a/b|0:this.bg(a,b)},
bg(a,b){var s=a/b
if(s>=-2147483648&&s<=2147483647)return s|0
if(s>0){if(s!==1/0)return Math.floor(s)}else if(s>-1/0)return Math.ceil(s)
throw A.b(A.e0("Result of truncating division is "+A.p(s)+": "+A.p(a)+" ~/ "+b))},
ah(a,b){return b>31?0:a<<b>>>0},
H(a,b){var s
if(a>0)s=this.be(a,b)
else{s=b>31?31:b
s=a>>s>>>0}return s},
cb(a,b){if(0>b)throw A.b(A.bw(b))
return this.be(a,b)},
be(a,b){return b>31?0:a>>>b},
gl(a){return A.ab(t.o)},
$im:1,
$ib4:1}
J.bI.prototype={
gl(a){return A.ab(t.S)},
$il:1,
$ic:1}
J.cM.prototype={
gl(a){return A.ab(t.i)},
$il:1}
J.b7.prototype={
a5(a,b,c){return a.substring(b,A.bX(b,c,a.length))},
i(a){return a},
gp(a){var s,r,q
for(s=a.length,r=0,q=0;q<s;++q){r=r+a.charCodeAt(q)&536870911
r=r+((r&524287)<<10)&536870911
r^=r>>6}r=r+((r&67108863)<<3)&536870911
r^=r>>11
return r+((r&16383)<<15)&536870911},
gl(a){return A.ab(t.N)},
gk(a){return a.length},
$il:1,
$ih2:1,
$ia7:1}
A.d7.prototype={
j(a,b){var s,r,q=this
t.L.a(b)
s=b.length
if(s===0)return
r=q.a+s
if(q.b.length<r)q.b8(r)
B.c.P(q.b,q.a,r,b)
q.a=r},
D(a){var s=this,r=s.b,q=s.a
if(r.length===q)s.b8(q)
r=s.b
q=s.a
r.$flags&2&&A.z(r)
if(!(q<r.length))return A.a(r,q)
r[q]=a
s.a=q+1},
b8(a){var s,r,q,p=a*2
if(p<1024)p=1024
else{s=p-1
s|=B.b.H(s,1)
s|=s>>>2
s|=s>>>4
s|=s>>>8
p=((s|s>>>16)>>>0)+1}r=new Uint8Array(p)
q=this.b
B.c.P(r,0,q.length,q)
this.b=r},
aP(){var s,r=this
if(r.a===0)return $.by()
s=J.cu(B.c.gI(r.b),r.b.byteOffset,r.a)
r.a=0
r.b=$.by()
return s},
cB(){var s=this
if(s.a===0)return $.by()
return new Uint8Array(A.L(J.cu(B.c.gI(s.b),s.b.byteOffset,s.a)))},
gk(a){return this.a},
N(a){this.a=0
this.b=$.by()},
$ife:1}
A.d5.prototype={
j(a,b){t.L.a(b)
B.a.j(this.b,b)
this.a=this.a+b.length},
D(a){var s=new Uint8Array(1)
s[0]=a
B.a.j(this.b,s);++this.a},
aP(){var s,r,q,p,o,n,m,l=this,k=l.a
if(k===0)return $.by()
s=l.b
r=s.length
if(r===1){if(0>=r)return A.a(s,0)
q=s[0]
l.a=0
B.a.N(s)
return q}q=new Uint8Array(k)
for(p=0,o=0;o<s.length;s.length===r||(0,A.b5)(s),++o,p=m){n=s[o]
m=p+n.length
B.c.P(q,p,m,n)}l.a=0
B.a.N(s)
return q},
gk(a){return this.a},
$ife:1}
A.ba.prototype={
i(a){return"LateInitializationError: "+this.a}}
A.cC.prototype={
gk(a){return this.a.length},
m(a,b){var s=this.a
if(!(b>=0&&b<s.length))return A.a(s,b)
return s.charCodeAt(b)}}
A.f7.prototype={
$0(){var s=new A.j($.i,t.D)
s.a7(null)
return s},
$S:10}
A.dR.prototype={}
A.bD.prototype={}
A.aK.prototype={
gE(a){var s=this
return new A.aL(s,s.gk(s),A.B(s).h("aL<aK.E>"))},
ga0(a){return this.gk(this)===0}}
A.c0.prototype={
gbU(){var s=J.cv(this.a),r=this.c
if(r==null||r>s)return s
return r},
gcc(){var s=J.cv(this.a),r=this.b
if(r>s)return s
return r},
gk(a){var s,r=J.cv(this.a),q=this.b
if(q>=r)return 0
s=this.c
if(s==null||s>=r)return r-q
return s-q},
X(a,b){var s=this,r=s.gcc()+b
if(b<0||r>=s.gbU())throw A.b(A.ff(b,s.gk(0),s,"index"))
return J.ic(s.a,r)},
ap(a,b){var s,r,q=this
A.bW(b,"count")
s=q.b+b
r=q.c
if(r!=null&&s>=r)return new A.bE(q.$ti.h("bE<1>"))
return A.cX(q.a,s,r,q.$ti.c)}}
A.aL.prototype={
gv(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s,r=this,q=r.a,p=J.cr(q),o=p.gk(q)
if(r.b!==o)throw A.b(A.bC(q))
s=r.c
if(s>=o){r.d=null
return!1}r.d=p.X(q,s);++r.c
return!0},
$iad:1}
A.bE.prototype={
gE(a){return B.a2},
gk(a){return 0}}
A.bF.prototype={
n(){return!1},
gv(){throw A.b(A.fT())},
$iad:1}
A.O.prototype={}
A.aS.prototype={
q(a,b,c){A.B(this).h("aS.E").a(c)
throw A.b(A.e0("Cannot modify an unmodifiable list"))}}
A.bk.prototype={}
A.bq.prototype={$r:"+(1,2)",$s:1}
A.bY.prototype={}
A.dW.prototype={
G(a){var s,r,q=this,p=new RegExp(q.a).exec(a)
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
A.bS.prototype={
i(a){return"Null check operator used on a null value"}}
A.cN.prototype={
i(a){var s,r=this,q="NoSuchMethodError: method not found: '",p=r.b
if(p==null)return"NoSuchMethodError: "+r.a
s=r.c
if(s==null)return q+p+"' ("+r.a+")"
return q+p+"' on '"+s+"' ("+r.a+")"}}
A.d0.prototype={
i(a){var s=this.a
return s.length===0?"Error":"Error: "+s}}
A.dP.prototype={
i(a){return"Throw of null ('"+(this.a===null?"null":"undefined")+"' from JavaScript)"}}
A.bG.prototype={}
A.cd.prototype={
i(a){var s,r=this.b
if(r!=null)return r
r=this.a
s=r!==null&&typeof r==="object"?r.stack:null
return this.b=s==null?"":s},
$ia6:1}
A.aw.prototype={
i(a){var s=this.constructor,r=s==null?null:s.name
return"Closure '"+A.hV(r==null?"unknown":r)+"'"},
gl(a){var s=A.fC(this)
return A.ab(s==null?A.au(this):s)},
$iaI:1,
gcG(){return this},
$C:"$1",
$R:1,
$D:null}
A.cA.prototype={$C:"$0",$R:0}
A.cB.prototype={$C:"$2",$R:2}
A.cY.prototype={}
A.cV.prototype={
i(a){var s=this.$static_name
if(s==null)return"Closure of unknown static method"
return"Closure '"+A.hV(s)+"'"}}
A.b6.prototype={
K(a,b){if(b==null)return!1
if(this===b)return!0
if(!(b instanceof A.b6))return!1
return this.$_target===b.$_target&&this.a===b.a},
gp(a){return(A.hQ(this.a)^A.bU(this.$_target))>>>0},
i(a){return"Closure '"+this.$_name+"' of "+("Instance of '"+A.cR(this.a)+"'")}}
A.cS.prototype={
i(a){return"RuntimeError: "+this.a}}
A.aJ.prototype={
gk(a){return this.a},
ga0(a){return this.a===0},
gaO(){return new A.bO(this,this.$ti.h("bO<1>"))},
m(a,b){var s,r,q,p,o=null
if(typeof b=="string"){s=this.b
if(s==null)return o
r=s[b]
q=r==null?o:r.b
return q}else if(typeof b=="number"&&(b&0x3fffffff)===b){p=this.c
if(p==null)return o
r=p[b]
q=r==null?o:r.b
return q}else return this.cs(b)},
cs(a){var s,r,q=this.d
if(q==null)return null
s=this.bZ(q,a)
r=this.bs(s,a)
if(r<0)return null
return s[r].b},
q(a,b,c){var s,r,q,p,o,n,m=this,l=m.$ti
l.c.a(b)
l.y[1].a(c)
if(typeof b=="string"){s=m.b
m.aU(s==null?m.b=m.aB():s,b,c)}else if(typeof b=="number"&&(b&0x3fffffff)===b){r=m.c
m.aU(r==null?m.c=m.aB():r,b,c)}else{q=m.d
if(q==null)q=m.d=m.aB()
p=J.Q(b)&1073741823
o=q[p]
if(o==null)q[p]=[m.au(b,c)]
else{n=m.bs(o,b)
if(n>=0)o[n].b=c
else o.push(m.au(b,c))}}},
Y(a,b){var s,r,q=this
q.$ti.h("~(1,2)").a(b)
s=q.e
r=q.r
while(s!=null){b.$2(s.a,s.b)
if(r!==q.r)throw A.b(A.bC(q))
s=s.c}},
aU(a,b,c){var s,r=this.$ti
r.c.a(b)
r.y[1].a(c)
s=a[b]
if(s==null)a[b]=this.au(b,c)
else s.b=c},
au(a,b){var s=this,r=s.$ti,q=new A.dG(r.c.a(a),r.y[1].a(b))
if(s.e==null)s.e=s.f=q
else s.f=s.f.c=q;++s.a
s.r=s.r+1&1073741823
return q},
bZ(a,b){return a[J.Q(b)&1073741823]},
bs(a,b){var s,r
if(a==null)return-1
s=a.length
for(r=0;r<s;++r)if(J.ct(a[r].a,b))return r
return-1},
i(a){return A.fZ(this)},
aB(){var s=Object.create(null)
s["<non-identifier-key>"]=s
delete s["<non-identifier-key>"]
return s},
$ifW:1}
A.dG.prototype={}
A.bO.prototype={
gk(a){return this.a.a},
ga0(a){return this.a.a===0},
gE(a){var s=this.a
return new A.bN(s,s.r,s.e,this.$ti.h("bN<1>"))}}
A.bN.prototype={
gv(){return this.d},
n(){var s,r=this,q=r.a
if(r.b!==q.r)throw A.b(A.bC(q))
s=r.c
if(s==null){r.d=null
return!1}else{r.d=s.a
r.c=s.c
return!0}},
$iad:1}
A.f2.prototype={
$1(a){return this.a(a)},
$S:3}
A.f3.prototype={
$2(a,b){return this.a(a,b)},
$S:11}
A.f4.prototype={
$1(a){return this.a(A.aq(a))},
$S:12}
A.aY.prototype={
gl(a){return A.ab(this.b7())},
b7(){return A.kx(this.$r,this.b6())},
i(a){return this.bi(!1)},
bi(a){var s,r,q,p,o,n=this.bX(),m=this.b6(),l=(a?"Record ":"")+"("
for(s=n.length,r="",q=0;q<s;++q,r=", "){l+=r
p=n[q]
if(typeof p=="string")l=l+p+": "
if(!(q<m.length))return A.a(m,q)
o=m[q]
l=a?l+A.h5(o):l+A.p(o)}l+=")"
return l.charCodeAt(0)==0?l:l},
bX(){var s,r=this.$s
while($.ew.length<=r)B.a.j($.ew,null)
s=$.ew[r]
if(s==null){s=this.bQ()
B.a.q($.ew,r,s)}return s},
bQ(){var s,r,q,p=this.$r,o=p.indexOf("("),n=p.substring(1,o),m=p.substring(o),l=m==="()"?0:m.replace(/[^,]/g,"").length+1,k=A.f(new Array(l),t.f)
for(s=0;s<l;++s)k[s]=s
if(n!==""){r=n.split(",")
s=r.length
for(q=l;s>0;){--q;--s
B.a.q(k,q,r[s])}}k=A.ix(k,!1,t.K)
k.$flags=3
return k}}
A.bp.prototype={
b6(){return[this.a,this.b]},
K(a,b){if(b==null)return!1
return b instanceof A.bp&&this.$s===b.$s&&J.ct(this.a,b.a)&&J.ct(this.b,b.b)},
gp(a){return A.h1(this.$s,this.a,this.b,B.i,B.i)}}
A.ed.prototype={}
A.ay.prototype={
gl(a){return B.aP},
aj(a,b,c){A.eR(a,b,c)
return c==null?new Uint8Array(a,b):new Uint8Array(a,b,c)},
bk(a,b){return this.aj(a,b,null)},
bj(a,b,c){var s
A.eR(a,b,c)
s=new DataView(a,b,c)
return s},
$il:1,
$iay:1,
$ibB:1}
A.bb.prototype={$ibb:1}
A.bR.prototype={
gI(a){if(((a.$flags|0)&2)!==0)return new A.dh(a.buffer)
else return a.buffer},
c_(a,b,c,d){var s=A.a4(b,0,c,d,null)
throw A.b(s)},
b0(a,b,c,d){if(b>>>0!==b||b>c)this.c_(a,b,c,d)},
$it:1}
A.dh.prototype={
aj(a,b,c){var s=A.iF(this.a,b,c)
s.$flags=3
return s},
bk(a,b){return this.aj(0,b,null)},
bj(a,b,c){var s=A.iE(this.a,b,c)
s.$flags=3
return s},
$ibB:1}
A.aN.prototype={
gl(a){return B.aQ},
$il:1,
$iaN:1,
$idw:1}
A.C.prototype={
gk(a){return a.length},
$iU:1}
A.bQ.prototype={
m(a,b){A.ar(b,a,a.length)
return a[b]},
q(a,b,c){A.dj(c)
a.$flags&2&&A.z(a)
A.ar(b,a,a.length)
a[b]=c},
$ie:1,
$ik:1}
A.V.prototype={
q(a,b,c){A.aa(c)
a.$flags&2&&A.z(a)
A.ar(b,a,a.length)
a[b]=c},
P(a,b,c,d){var s,r,q,p
t.hb.a(d)
a.$flags&2&&A.z(a,5)
if(t.eB.b(d)){s=a.length
this.b0(a,b,s,"start")
this.b0(a,c,s,"end")
if(b>c)A.n(A.a4(b,0,c,null,null))
r=c-b
q=d.length
if(q<r)A.n(A.ae("Not enough elements"))
p=q!==r?d.subarray(0,r):d
a.set(p,b)
return}this.bJ(a,b,c,d,0)},
$ie:1,
$ik:1}
A.bc.prototype={
gl(a){return B.aR},
$il:1,
$ibc:1,
$idz:1}
A.bd.prototype={
gl(a){return B.aS},
$il:1,
$ibd:1,
$idA:1}
A.be.prototype={
gl(a){return B.aT},
m(a,b){A.ar(b,a,a.length)
return a[b]},
$il:1,
$ibe:1,
$idB:1}
A.bf.prototype={
gl(a){return B.aU},
m(a,b){A.ar(b,a,a.length)
return a[b]},
$il:1,
$ibf:1,
$idC:1}
A.bg.prototype={
gl(a){return B.aV},
m(a,b){A.ar(b,a,a.length)
return a[b]},
$il:1,
$ibg:1,
$idD:1}
A.bh.prototype={
gl(a){return B.aY},
m(a,b){A.ar(b,a,a.length)
return a[b]},
$il:1,
$ibh:1,
$idY:1}
A.bi.prototype={
gl(a){return B.aZ},
m(a,b){A.ar(b,a,a.length)
return a[b]},
$il:1,
$ibi:1,
$idZ:1}
A.aO.prototype={
gl(a){return B.b_},
gk(a){return a.length},
m(a,b){A.ar(b,a,a.length)
return a[b]},
$il:1,
$iaO:1,
$ie_:1}
A.az.prototype={
gl(a){return B.b0},
gk(a){return a.length},
m(a,b){A.ar(b,a,a.length)
return a[b]},
a4(a,b,c){return new Uint8Array(a.subarray(b,A.aE(b,c,a.length)))},
$il:1,
$iaz:1,
$iam:1}
A.c8.prototype={}
A.c9.prototype={}
A.ca.prototype={}
A.cb.prototype={}
A.a5.prototype={
h(a){return A.cl(v.typeUniverse,this,a)},
B(a){return A.hp(v.typeUniverse,this,a)}}
A.dc.prototype={}
A.eB.prototype={
i(a){return A.M(this.a,null)}}
A.db.prototype={
i(a){return this.a}}
A.ch.prototype={$iak:1}
A.e9.prototype={
$1(a){var s=this.a,r=s.a
s.a=null
r.$0()},
$S:4}
A.e8.prototype={
$1(a){var s,r
this.a.a=t.M.a(a)
s=this.b
r=this.c
s.firstChild?s.removeChild(r):s.appendChild(r)},
$S:13}
A.ea.prototype={
$0(){this.a.$0()},
$S:5}
A.eb.prototype={
$0(){this.a.$0()},
$S:5}
A.ez.prototype={
bK(a,b){if(self.setTimeout!=null)self.setTimeout(A.dp(new A.eA(this,b),0),a)
else throw A.b(A.e0("`setTimeout()` not found."))}}
A.eA.prototype={
$0(){this.b.$0()},
$S:0}
A.c3.prototype={
aL(a){var s,r=this,q=r.$ti
q.h("1/?").a(a)
if(a==null)a=q.c.a(a)
if(!r.b)r.a.a7(a)
else{s=r.a
if(q.h("J<1>").b(a))s.b_(a)
else s.b2(a)}},
bn(a,b){var s=this.a
if(this.b)s.a9(new A.N(a,b))
else s.R(new A.N(a,b))},
$idy:1}
A.eO.prototype={
$1(a){return this.a.$2(0,a)},
$S:14}
A.eP.prototype={
$2(a,b){this.a.$2(1,new A.bG(a,t.l.a(b)))},
$S:15}
A.eX.prototype={
$2(a,b){this.a(A.aa(a),b)},
$S:16}
A.A.prototype={
gv(){var s=this.b
return s==null?this.$ti.c.a(s):s},
c7(a,b){var s,r,q
a=A.aa(a)
b=b
s=this.a
for(;;)try{r=s(this,a,b)
return r}catch(q){b=q
a=1}},
n(){var s,r,q,p,o=this,n=null,m=0
for(;;){s=o.d
if(s!=null)try{if(s.n()){o.b=s.gv()
return!0}else o.d=null}catch(r){n=r
m=1
o.d=null}q=o.c7(m,n)
if(1===q)return!0
if(0===q){o.b=null
p=o.e
if(p==null||p.length===0){o.a=A.hj
return!1}if(0>=p.length)return A.a(p,-1)
o.a=p.pop()
m=0
n=null
continue}if(2===q){m=0
n=null
continue}if(3===q){n=o.c
o.c=null
p=o.e
if(p==null||p.length===0){o.b=null
o.a=A.hj
throw n
return!1}if(0>=p.length)return A.a(p,-1)
o.a=p.pop()
m=1
continue}throw A.b(A.ae("sync*"))}return!1},
cK(a){var s,r,q=this
if(a instanceof A.br){s=a.a()
r=q.e
if(r==null)r=q.e=[]
B.a.j(r,q.a)
q.a=s
return 2}else{q.d=J.fc(a)
return 2}},
$iad:1}
A.br.prototype={
gE(a){return new A.A(this.a(),this.$ti.h("A<1>"))}}
A.N.prototype={
i(a){return A.p(this.a)},
$iq:1,
gaq(){return this.b}}
A.c5.prototype={
bn(a,b){var s=this.a
if((s.a&30)!==0)throw A.b(A.ae("Future already completed"))
s.R(A.jF(a,b))},
$idy:1}
A.bl.prototype={
aL(a){var s,r=this.$ti
r.h("1/?").a(a)
s=this.a
if((s.a&30)!==0)throw A.b(A.ae("Future already completed"))
s.a7(r.h("1/").a(a))},
cj(){return this.aL(null)}}
A.an.prototype={
cu(a){var s
if((this.c&15)!==6)return!0
s=this.b.b
return s.ae(s,t.al.a(this.d),a.a,t.y,t.K)},
cq(a){var s,r=this,q=r.e,p=null,o=t.z,n=t.K,m=a.a,l=r.b.b
if(t.C.b(q))p=l.c8(l,q,m,a.b,o,n,t.l)
else p=l.ae(l,t.v.a(q),m,o,n)
try{o=r.$ti.h("2/").a(p)
return o}catch(s){if(t.eK.b(A.P(s))){if((r.c&1)!==0)throw A.b(A.cx("The error handler of Future.then must return a value of the returned future's type","onError"))
throw A.b(A.cx("The error handler of Future.catchError must return a value of the future's type","onError"))}else throw s}}}
A.j.prototype={
ak(a,b,c){var s,r,q,p=this.$ti
p.B(c).h("1/(2)").a(a)
s=$.i
if(s===B.d){if(b!=null&&!t.C.b(b)&&!t.v.b(b))throw A.b(A.av(b,"onError",u.c))}else{r=p.c
a=s.ac(s,c.h("@<0/>").B(r).h("1(2)").a(a),c.h("0/"),r)
if(b!=null)b=A.k5(b,s)}q=new A.j(s,c.h("j<0>"))
r=b==null?1:3
this.a6(new A.an(q,r,a,b,p.h("@<1>").B(c).h("an<1,2>")))
return q},
cA(a,b){return this.ak(a,null,b)},
bh(a,b,c){var s,r=this.$ti
r.B(c).h("1/(2)").a(a)
s=new A.j($.i,c.h("j<0>"))
this.a6(new A.an(s,19,a,b,r.h("@<1>").B(c).h("an<1,2>")))
return s},
aQ(a){var s,r,q
t.O.a(a)
s=this.$ti
r=$.i
q=new A.j(r,s)
if(r!==B.d)a=r.ab(r,a,t.z)
this.a6(new A.an(q,8,a,null,s.h("an<1,1>")))
return q},
c9(a){this.a=this.a&1|16
this.c=a},
a8(a){this.a=a.a&30|this.a&1
this.c=a.c},
a6(a){var s,r=this,q=r.a
if(q<=3){a.a=t.F.a(r.c)
r.c=a}else{if((q&4)!==0){s=t._.a(r.c)
if((s.a&24)===0){s.a6(a)
return}r.a8(s)}q=r.b
q.V(q,new A.eg(r,a))}},
bd(a){var s,r,q,p,o,n,m=this,l={}
l.a=a
if(a==null)return
s=m.a
if(s<=3){r=t.F.a(m.c)
m.c=a
if(r!=null){q=a.a
for(p=a;q!=null;p=q,q=o)o=q.a
p.a=r}}else{if((s&4)!==0){n=t._.a(m.c)
if((n.a&24)===0){n.bd(a)
return}m.a8(n)}l.a=m.ad(a)
s=m.b
s.V(s,new A.ek(l,m))}},
U(){var s=t.F.a(this.c)
this.c=null
return this.ad(s)},
ad(a){var s,r,q
for(s=a,r=null;s!=null;r=s,s=q){q=s.a
s.a=r}return r},
b2(a){var s,r=this
r.$ti.c.a(a)
s=r.U()
r.a=8
r.c=a
A.aW(r,s)},
bP(a){var s=this.U()
this.a8(a)
A.aW(this,s)},
a9(a){var s=this.U()
this.c9(a)
A.aW(this,s)},
bO(a,b){A.ap(a)
t.l.a(b)
this.a9(new A.N(a,b))},
a7(a){var s=this.$ti
s.h("1/").a(a)
if(s.h("J<1>").b(a)){this.b_(a)
return}this.bM(a)},
bM(a){var s,r=this
r.$ti.c.a(a)
r.a^=2
s=r.b
s.V(s,new A.ei(r,a))},
b_(a){A.fo(this.$ti.h("J<1>").a(a),this,!1)
return},
R(a){var s
this.a^=2
s=this.b
s.V(s,new A.eh(this,a))},
$iJ:1}
A.eg.prototype={
$0(){A.aW(this.a,this.b)},
$S:0}
A.ek.prototype={
$0(){A.aW(this.b,this.a.a)},
$S:0}
A.ej.prototype={
$0(){A.fo(this.a.a,this.b,!0)},
$S:0}
A.ei.prototype={
$0(){this.a.b2(this.b)},
$S:0}
A.eh.prototype={
$0(){this.a.a9(this.b)},
$S:0}
A.en.prototype={
$0(){var s,r,q,p,o,n,m,l,k=this,j=null
try{q=k.a.a
p=q.b.b
j=p.af(p,t.O.a(q.d),t.z)}catch(o){s=A.P(o)
r=A.S(o)
if(k.c&&t.n.a(k.b.a.c).a===s){q=k.a
q.c=t.n.a(k.b.a.c)}else{q=s
p=r
if(p==null)p=A.dv(q)
n=k.a
n.c=new A.N(q,p)
q=n}q.b=!0
return}if(j instanceof A.j&&(j.a&24)!==0){if((j.a&16)!==0){q=k.a
q.c=t.n.a(j.c)
q.b=!0}return}if(j instanceof A.j){m=k.b.a
l=new A.j(m.b,m.$ti)
j.ak(new A.eo(l,m),new A.ep(l),t.H)
q=k.a
q.c=l
q.b=!1}},
$S:0}
A.eo.prototype={
$1(a){this.a.bP(this.b)},
$S:4}
A.ep.prototype={
$2(a,b){A.ap(a)
t.l.a(b)
this.a.a9(new A.N(a,b))},
$S:7}
A.em.prototype={
$0(){var s,r,q,p,o,n,m,l,k
try{q=this.a
p=q.a
o=p.$ti
n=o.c
m=n.a(this.b)
l=p.b.b
q.c=l.ae(l,o.h("2/(1)").a(p.d),m,o.h("2/"),n)}catch(k){s=A.P(k)
r=A.S(k)
q=s
p=r
if(p==null)p=A.dv(q)
o=this.a
o.c=new A.N(q,p)
o.b=!0}},
$S:0}
A.el.prototype={
$0(){var s,r,q,p,o,n,m,l=this
try{s=t.n.a(l.a.a.c)
p=l.b
if(p.a.cu(s)&&p.a.e!=null){p.c=p.a.cq(s)
p.b=!1}}catch(o){r=A.P(o)
q=A.S(o)
p=t.n.a(l.a.a.c)
if(p.a===r){n=l.b
n.c=p
p=n}else{p=r
n=q
if(n==null)n=A.dv(p)
m=l.b
m.c=new A.N(p,n)
p=m}p.b=!0}},
$S:0}
A.d2.prototype={}
A.c_.prototype={
gk(a){var s={},r=new A.j($.i,t.fJ)
s.a=0
this.bu(new A.dT(s,this),!0,new A.dU(s,r),r.gbN())
return r}}
A.dT.prototype={
$1(a){this.b.$ti.c.a(a);++this.a.a},
$S(){return this.b.$ti.h("~(1)")}}
A.dU.prototype={
$0(){var s=this.b,r=s.$ti,q=r.h("1/").a(this.a.a),p=s.U()
r.c.a(q)
s.a=8
s.c=q
A.aW(s,p)},
$S:0}
A.ce.prototype={
gc4(){var s,r=this
if((r.b&8)===0)return A.B(r).h("a8<1>?").a(r.a)
s=A.B(r)
return s.h("a8<1>?").a(s.h("cf<1>").a(r.a).gaI())},
b4(){var s,r,q=this
if((q.b&8)===0){s=q.a
if(s==null)s=q.a=new A.a8(A.B(q).h("a8<1>"))
return A.B(q).h("a8<1>").a(s)}r=A.B(q)
s=r.h("cf<1>").a(q.a).gaI()
return r.h("a8<1>").a(s)},
gbf(){var s=this.a
if((this.b&8)!==0)s=t.fv.a(s).gaI()
return A.B(this).h("bo<1>").a(s)},
aY(){if((this.b&4)!==0)return new A.aA("Cannot add event after closing")
return new A.aA("Cannot add event while adding a stream")},
b3(){var s=this.c
if(s==null)s=this.c=(this.b&2)!==0?$.fa():new A.j($.i,t.D)
return s},
j(a,b){var s,r=this,q=A.B(r)
q.c.a(b)
s=r.b
if(s>=4)throw A.b(r.aY())
if((s&1)!==0)r.aG(b)
else if((s&3)===0)r.b4().j(0,new A.aU(b,q.h("aU<1>")))},
u(){var s=this,r=s.b
if((r&4)!==0)return s.b3()
if(r>=4)throw A.b(s.aY())
r=s.b=r|4
if((r&1)!==0)s.aH()
else if((r&3)===0)s.b4().j(0,B.A)
return s.b3()},
cd(a,b,c,d){var s,r,q,p,o,n,m,l,k,j=this,i=A.B(j)
i.h("~(1)?").a(a)
t.b.a(c)
if((j.b&3)!==0)throw A.b(A.ae("Stream has already been listened to."))
s=i.c
r=$.i
q=d?1:0
p=b!=null?32:0
o=t.H
s=r.ac(r,t.V.B(s).h("1(2)").a(a),o,s)
A.iY(r,b)
n=t.M
m=new A.bo(j,s,r.ab(r,n.a(c),o),r,q|p,i.h("bo<1>"))
l=j.gc4()
if(((j.b|=1)&8)!==0){k=i.h("cf<1>").a(j.a)
k.saI(m)
k.cv()}else j.a=m
m.ca(l)
i=n.a(new A.ey(j))
s=m.e
m.e=s|64
i.$0()
m.e&=4294967231
m.b1((s&4)!==0)
return m},
c5(a){var s,r,q,p,o,n,m,l,k=this,j=A.B(k)
j.h("cW<1>").a(a)
s=null
if((k.b&8)!==0)s=j.h("cf<1>").a(k.a).cL()
k.a=null
k.b=k.b&4294967286|2
r=k.r
if(r!=null)if(s==null)try{q=r.$0()
if(q instanceof A.j)s=q}catch(n){p=A.P(n)
o=A.S(n)
m=new A.j($.i,t.D)
j=A.ap(p)
l=t.l.a(o)
m.R(new A.N(j,l))
s=m}else s=s.aQ(r)
j=new A.ex(k)
if(s!=null)s=s.aQ(j)
else j.$0()
return s},
$ih8:1,
$ihi:1,
$iaV:1}
A.ey.prototype={
$0(){A.fy(this.a.d)},
$S:0}
A.ex.prototype={
$0(){var s=this.a.c
if(s!=null&&(s.a&30)===0)s.a7(null)},
$S:0}
A.d3.prototype={
aG(a){var s=this.$ti
s.c.a(a)
this.gbf().aW(new A.aU(a,s.h("aU<1>")))},
aH(){this.gbf().aW(B.A)}}
A.bm.prototype={}
A.bn.prototype={
gp(a){return(A.bU(this.a)^892482866)>>>0},
K(a,b){if(b==null)return!1
if(this===b)return!0
return b instanceof A.bn&&b.a===this.a}}
A.bo.prototype={
b9(){return this.w.c5(this)},
ba(){var s=this.w,r=A.B(s)
r.h("cW<1>").a(this)
if((s.b&8)!==0)r.h("cf<1>").a(s.a).cO()
A.fy(s.e)},
bb(){var s=this.w,r=A.B(s)
r.h("cW<1>").a(this)
if((s.b&8)!==0)r.h("cf<1>").a(s.a).cv()
A.fy(s.f)}}
A.c4.prototype={
ca(a){var s=this
A.B(s).h("a8<1>?").a(a)
if(a==null)return
s.r=a
if(a.c!=null){s.e|=128
a.ao(s)}},
aZ(){var s,r=this,q=r.e|=8
if((q&128)!==0){s=r.r
if(s.a===1)s.a=3}if((q&64)===0)r.r=null
r.f=r.b9()},
ba(){},
bb(){},
b9(){return null},
aW(a){var s,r=this,q=r.r
if(q==null)q=r.r=new A.a8(A.B(r).h("a8<1>"))
q.j(0,a)
s=r.e
if((s&128)===0){s|=128
r.e=s
if(s<256)q.ao(r)}},
aG(a){var s,r=this,q=A.B(r).c
q.a(a)
s=r.e
r.e=s|64
r.d.cz(r.a,a,q)
r.e&=4294967231
r.b1((s&4)!==0)},
aH(){var s,r=this,q=new A.ec(r)
r.aZ()
r.e|=16
s=r.f
if(s!=null&&s!==$.fa())s.aQ(q)
else q.$0()},
b1(a){var s,r,q=this,p=q.e
if((p&128)!==0&&q.r.c==null){p=q.e=p&4294967167
s=!1
if((p&4)!==0)if(p<256){s=q.r
s=s==null?null:s.c==null
s=s!==!1}if(s){p&=4294967291
q.e=p}}for(;;a=r){if((p&8)!==0){q.r=null
return}r=(p&4)!==0
if(a===r)break
q.e=p^64
if(r)q.ba()
else q.bb()
p=q.e&=4294967231}if((p&128)!==0&&p<256)q.r.ao(q)},
$icW:1,
$iaV:1}
A.ec.prototype={
$0(){var s=this.a,r=s.e
if((r&16)===0)return
s.e=r|74
s.d.cw(s.c)
s.e&=4294967231},
$S:0}
A.cg.prototype={
bu(a,b,c,d){var s=this.$ti
s.h("~(1)?").a(a)
t.b.a(c)
return this.a.cd(s.h("~(1)?").a(a),d,c,b===!0)},
ct(a,b){return this.bu(a,null,b,null)}}
A.aC.prototype={
sa2(a){this.a=t.ev.a(a)},
ga2(){return this.a}}
A.aU.prototype={
bv(a){this.$ti.h("aV<1>").a(a).aG(this.b)}}
A.d8.prototype={
bv(a){a.aH()},
ga2(){return null},
sa2(a){throw A.b(A.ae("No events after a done."))},
$iaC:1}
A.a8.prototype={
ao(a){var s,r=this
r.$ti.h("aV<1>").a(a)
s=r.a
if(s===1)return
if(s>=1){r.a=1
return}A.kN(new A.ev(r,a))
r.a=1},
j(a,b){var s=this,r=s.c
if(r==null)s.b=s.c=b
else{r.sa2(b)
s.c=b}}}
A.ev.prototype={
$0(){var s,r,q,p=this.a,o=p.a
p.a=0
if(o===3)return
s=p.$ti.h("aV<1>").a(this.b)
r=p.b
q=r.ga2()
p.b=q
if(q==null)p.c=null
r.bv(s)},
$S:0}
A.df.prototype={}
A.e5.prototype={
cw(a){var s,r,q,p,o=this
t.M.a(a)
try{q=o.af(o,a,t.H)
return q}catch(p){s=A.P(p)
r=A.S(p)
o.S(o,s,r)}},
cz(a,b,c){var s,r,q,p,o=this
c.h("~(0)").a(a)
c.a(b)
try{q=o.ae(o,a,b,t.H,c)
return q}catch(p){s=A.P(p)
r=A.S(p)
o.S(o,s,r)}},
cg(a,b){return new A.e6(this,this.ab(this,b.h("0()").a(a),b),b)},
S(a,b,c){var s,r,q,p,o,n,m,l
t.l.a(c)
s=null
if(s==null){A.k7(b,c)
return}r=s.gaR()
q=r.gcJ()
p=$.i
try{$.i=q
s.cp(r,r.gaD(),a,b,c)
$.i=p}catch(m){o=A.P(m)
n=A.S(m)
$.i=p
l=b===o?c:n
q.S(r,o,l)}},
af(a,b,c){var s,r,q
c.h("0()").a(b)
r=$.i
if(r===a)return b.$0()
s=r
$.i=a
try{r=b.$0()
return r}finally{$.i=s}q=null.gaR()
return null.cM(q,q.gaD(),a,b)},
ae(a,b,c,d,e){var s,r,q
d.h("@<0>").B(e).h("1(2)").a(b)
e.a(c)
r=$.i
if(r===a)return b.$1(c)
s=r
$.i=a
try{r=b.$1(c)
return r}finally{$.i=s}q=null.gaR()
return null.cp(q,q.gaD(),a,b,c)},
c8(a,b,c,d,e,f,g){var s,r,q
e.h("@<0>").B(f).B(g).h("1(2,3)").a(b)
f.a(c)
g.a(d)
r=$.i
if(r===a)return b.$2(c,d)
s=r
$.i=a
try{r=b.$2(c,d)
return r}finally{$.i=s}q=null.gaR()
return null.cN(q,q.gaD(),a,b,c,d)},
ab(a,b,c){c.h("0()").a(b)
return b},
ac(a,b,c,d){c.h("@<0>").B(d).h("1(2)").a(b)
return b},
aE(a,b,c,d,e){c.h("@<0>").B(d).B(e).h("1(2,3)").a(b)
return b},
bV(a,b,c){return null},
V(a,b){A.fx(a,t.M.a(b))
return}}
A.e6.prototype={
$0(){var s=this.a
return s.af(s,this.b,this.c)},
$S(){return this.c.h("0()")}}
A.eU.prototype={
$0(){A.ir(this.a,this.b)},
$S:0}
A.c6.prototype={
gE(a){var s=this,r=new A.c7(s,s.r,s.$ti.h("c7<1>"))
r.c=s.e
return r},
gk(a){return this.a},
ck(a,b){var s
if((b&1073741823)===b){s=this.c
if(s==null)return!1
return t.R.a(s[b])!=null}else return this.bR(b)},
bR(a){var s=this.d
if(s==null)return!1
return this.b5(s[B.b.gp(a)&1073741823],a)>=0},
j(a,b){var s,r,q=this
q.$ti.c.a(b)
if(typeof b=="string"&&b!=="__proto__"){s=q.b
return q.aV(s==null?q.b=A.fp():s,b)}else if(typeof b=="number"&&(b&1073741823)===b){r=q.c
return q.aV(r==null?q.c=A.fp():r,b)}else return q.bL(b)},
bL(a){var s,r,q,p=this
p.$ti.c.a(a)
s=p.d
if(s==null)s=p.d=A.fp()
r=J.Q(a)&1073741823
q=s[r]
if(q==null)s[r]=[p.aC(a)]
else{if(p.b5(q,a)>=0)return!1
q.push(p.aC(a))}return!0},
aV(a,b){this.$ti.c.a(b)
if(t.R.a(a[b])!=null)return!1
a[b]=this.aC(b)
return!0},
aC(a){var s=this,r=new A.dd(s.$ti.c.a(a))
if(s.e==null)s.e=s.f=r
else s.f=s.f.b=r;++s.a
s.r=s.r+1&1073741823
return r},
b5(a,b){var s,r
if(a==null)return-1
s=a.length
for(r=0;r<s;++r)if(J.ct(a[r].a,b))return r
return-1}}
A.dd.prototype={}
A.c7.prototype={
gv(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s=this,r=s.c,q=s.a
if(s.b!==q.r)throw A.b(A.bC(q))
else if(r==null){s.d=null
return!1}else{s.d=s.$ti.h("1?").a(r.a)
s.c=r.b
return!0}},
$iad:1}
A.h.prototype={
gE(a){return new A.aL(a,this.gk(a),A.au(a).h("aL<h.E>"))},
X(a,b){return this.m(a,b)},
gbt(a){return this.gk(a)!==0},
ap(a,b){return A.cX(a,b,null,A.au(a).h("h.E"))},
bx(a,b){return A.cX(a,0,A.dn(b,"count",t.S),A.au(a).h("h.E"))},
bF(a,b,c,d,e){var s,r,q
A.au(a).h("e<h.E>").a(d)
A.bX(b,c,this.gk(a))
s=c-b
if(s===0)return
A.bW(e,"skipCount")
r=J.cr(d)
if(e+s>r.gk(d))throw A.b(A.ae("Too few elements"))
if(e<b)for(q=s-1;q>=0;--q)this.q(a,b+q,r.m(d,e+q))
else for(q=0;q<s;++q)this.q(a,b+q,r.m(d,e+q))},
i(a){return A.fg(a,"[","]")},
$ie:1,
$ik:1}
A.R.prototype={
Y(a,b){var s,r,q,p=A.B(this)
p.h("~(R.K,R.V)").a(b)
for(s=this.gaO(),s=s.gE(s),p=p.h("R.V");s.n();){r=s.gv()
q=this.m(0,r)
b.$2(r,q==null?p.a(q):q)}},
gk(a){var s=this.gaO()
return s.gk(s)},
ga0(a){var s=this.gaO()
return s.ga0(s)},
i(a){return A.fZ(this)},
$idH:1}
A.dI.prototype={
$2(a,b){var s,r=this.a
if(!r.a)this.b.a+=", "
r.a=!1
r=this.b
s=A.p(a)
r.a=(r.a+=s)+": "
s=A.p(b)
r.a+=s},
$S:1}
A.bj.prototype={
i(a){return A.fg(this,"{","}")},
$ie:1}
A.cc.prototype={}
A.eF.prototype={
$0(){var s,r
try{s=new TextDecoder("utf-8",{fatal:true})
return s}catch(r){}return null},
$S:8}
A.eE.prototype={
$0(){var s,r
try{s=new TextDecoder("utf-8",{fatal:false})
return s}catch(r){}return null},
$S:8}
A.cD.prototype={}
A.cF.prototype={}
A.bM.prototype={
i(a){var s=A.cH(this.a)
return(this.b!=null?"Converting object to an encodable object failed:":"Converting object did not return an encodable object:")+" "+s}}
A.cP.prototype={
i(a){return"Cyclic error in JSON stringify"}}
A.cO.prototype={
cn(a,b){var s=A.j0(a,this.gco().b,null)
return s},
gco(){return B.aE}}
A.dF.prototype={}
A.es.prototype={
bD(a){var s,r,q,p,o,n,m=a.length
for(s=this.c,r=0,q=0;q<m;++q){p=a.charCodeAt(q)
if(p>92){if(p>=55296){o=p&64512
if(o===55296){n=q+1
n=!(n<m&&(a.charCodeAt(n)&64512)===56320)}else n=!1
if(!n)if(o===56320){o=q-1
o=!(o>=0&&(a.charCodeAt(o)&64512)===55296)}else o=!1
else o=!0
if(o){if(q>r)s.a+=B.m.a5(a,r,q)
r=q+1
o=A.v(92)
s.a+=o
o=A.v(117)
s.a+=o
o=A.v(100)
s.a+=o
o=p>>>8&15
o=A.v(o<10?48+o:87+o)
s.a+=o
o=p>>>4&15
o=A.v(o<10?48+o:87+o)
s.a+=o
o=p&15
o=A.v(o<10?48+o:87+o)
s.a+=o}}continue}if(p<32){if(q>r)s.a+=B.m.a5(a,r,q)
r=q+1
o=A.v(92)
s.a+=o
switch(p){case 8:o=A.v(98)
s.a+=o
break
case 9:o=A.v(116)
s.a+=o
break
case 10:o=A.v(110)
s.a+=o
break
case 12:o=A.v(102)
s.a+=o
break
case 13:o=A.v(114)
s.a+=o
break
default:o=A.v(117)
s.a+=o
o=A.v(48)
s.a=(s.a+=o)+o
o=p>>>4&15
o=A.v(o<10?48+o:87+o)
s.a+=o
o=p&15
o=A.v(o<10?48+o:87+o)
s.a+=o
break}}else if(p===34||p===92){if(q>r)s.a+=B.m.a5(a,r,q)
r=q+1
o=A.v(92)
s.a+=o
o=A.v(p)
s.a+=o}}if(r===0)s.a+=a
else if(r<m)s.a+=B.m.a5(a,r,m)},
av(a){var s,r,q,p
for(s=this.a,r=s.length,q=0;q<r;++q){p=s[q]
if(a==null?p==null:a===p)throw A.b(new A.cP(a,null))}B.a.j(s,a)},
an(a){var s,r,q,p,o=this
if(o.bC(a))return
o.av(a)
try{s=o.b.$1(a)
if(!o.bC(s)){q=A.fU(a,null,o.gbc())
throw A.b(q)}q=o.a
if(0>=q.length)return A.a(q,-1)
q.pop()}catch(p){r=A.P(p)
q=A.fU(a,r,o.gbc())
throw A.b(q)}},
bC(a){var s,r,q=this
if(typeof a=="number"){if(!isFinite(a))return!1
q.c.a+=B.I.i(a)
return!0}else if(a===!0){q.c.a+="true"
return!0}else if(a===!1){q.c.a+="false"
return!0}else if(a==null){q.c.a+="null"
return!0}else if(typeof a=="string"){s=q.c
s.a+='"'
q.bD(a)
s.a+='"'
return!0}else if(t.j.b(a)){q.av(a)
q.cE(a)
s=q.a
if(0>=s.length)return A.a(s,-1)
s.pop()
return!0}else if(a instanceof A.R){q.av(a)
r=q.cF(a)
s=q.a
if(0>=s.length)return A.a(s,-1)
s.pop()
return r}else return!1},
cE(a){var s,r,q=this.c
q.a+="["
s=J.dr(a)
if(s.gbt(a)){this.an(s.m(a,0))
for(r=1;r<s.gk(a);++r){q.a+=","
this.an(s.m(a,r))}}q.a+="]"},
cF(a){var s,r,q,p,o,n,m=this,l={}
if(a.ga0(a)){m.c.a+="{}"
return!0}s=a.gk(a)*2
r=A.aM(s,null,!1,t.X)
q=l.a=0
l.b=!0
a.Y(0,new A.et(l,r))
if(!l.b)return!1
p=m.c
p.a+="{"
for(o='"';q<s;q+=2,o=',"'){p.a+=o
m.bD(A.aq(r[q]))
p.a+='":'
n=q+1
if(!(n<s))return A.a(r,n)
m.an(r[n])}p.a+="}"
return!0}}
A.et.prototype={
$2(a,b){var s,r
if(typeof a!="string")this.a.b=!1
s=this.b
r=this.a
B.a.q(s,r.a++,a)
B.a.q(s,r.a++,b)},
$S:1}
A.er.prototype={
gbc(){var s=this.c.a
return s.charCodeAt(0)==0?s:s}}
A.e2.prototype={
J(a){var s,r,q,p=a.length,o=A.bX(0,null,p)
if(o===0)return new Uint8Array(0)
s=new Uint8Array(o*3)
r=new A.eG(s)
if(r.bY(a,0,o)!==o){q=o-1
if(!(q>=0&&q<p))return A.a(a,q)
r.aJ()}return B.c.a4(s,0,r.b)}}
A.eG.prototype={
aJ(){var s,r=this,q=r.c,p=r.b,o=r.b=p+1
q.$flags&2&&A.z(q)
s=q.length
if(!(p<s))return A.a(q,p)
q[p]=239
p=r.b=o+1
if(!(o<s))return A.a(q,o)
q[o]=191
r.b=p+1
if(!(p<s))return A.a(q,p)
q[p]=189},
ce(a,b){var s,r,q,p,o,n=this
if((b&64512)===56320){s=65536+((a&1023)<<10)|b&1023
r=n.c
q=n.b
p=n.b=q+1
r.$flags&2&&A.z(r)
o=r.length
if(!(q<o))return A.a(r,q)
r[q]=s>>>18|240
q=n.b=p+1
if(!(p<o))return A.a(r,p)
r[p]=s>>>12&63|128
p=n.b=q+1
if(!(q<o))return A.a(r,q)
r[q]=s>>>6&63|128
n.b=p+1
if(!(p<o))return A.a(r,p)
r[p]=s&63|128
return!0}else{n.aJ()
return!1}},
bY(a,b,c){var s,r,q,p,o,n,m,l,k=this
if(b!==c){s=c-1
if(!(s>=0&&s<a.length))return A.a(a,s)
s=(a.charCodeAt(s)&64512)===55296}else s=!1
if(s)--c
for(s=k.c,r=s.$flags|0,q=s.length,p=a.length,o=b;o<c;++o){if(!(o<p))return A.a(a,o)
n=a.charCodeAt(o)
if(n<=127){m=k.b
if(m>=q)break
k.b=m+1
r&2&&A.z(s)
s[m]=n}else{m=n&64512
if(m===55296){if(k.b+4>q)break
m=o+1
if(!(m<p))return A.a(a,m)
if(k.ce(n,a.charCodeAt(m)))o=m}else if(m===56320){if(k.b+3>q)break
k.aJ()}else if(n<=2047){m=k.b
l=m+1
if(l>=q)break
k.b=l
r&2&&A.z(s)
if(!(m<q))return A.a(s,m)
s[m]=n>>>6|192
k.b=l+1
s[l]=n&63|128}else{m=k.b
if(m+2>=q)break
l=k.b=m+1
r&2&&A.z(s)
if(!(m<q))return A.a(s,m)
s[m]=n>>>12|224
m=k.b=l+1
if(!(l<q))return A.a(s,l)
s[l]=n>>>6&63|128
k.b=m+1
if(!(m<q))return A.a(s,m)
s[m]=n&63|128}}}return o}}
A.e1.prototype={
J(a){return new A.eD(this.a).bT(t.L.a(a),0,null,!0)}}
A.eD.prototype={
bT(a,b,c,d){var s,r,q,p,o,n,m,l=this
t.L.a(a)
s=A.bX(b,c,a.length)
if(b===s)return""
if(a instanceof Uint8Array){r=a
q=r
p=0}else{q=A.jk(a,b,s)
s-=b
p=b
b=0}if(s-b>=15){o=l.a
n=A.jj(o,q,b,s)
if(n!=null){if(!o)return n
if(n.indexOf("\ufffd")<0)return n}}n=l.aw(q,b,s,!0)
o=l.b
if((o&1)!==0){m=A.jl(o)
l.b=0
throw A.b(A.a3(m,a,p+l.c))}return n},
aw(a,b,c,d){var s,r,q=this
if(c-b>1000){s=B.b.F(b+c,2)
r=q.aw(a,b,s,!1)
if((q.b&1)!==0)return r
return r+q.aw(a,s,c,d)}return q.cl(a,b,c,d)},
cl(a,b,a0,a1){var s,r,q,p,o,n,m,l,k=this,j="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFFFFFFFFFFFFFFFFGGGGGGGGGGGGGGGGHHHHHHHHHHHHHHHHHHHHHHHHHHHIHHHJEEBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBKCCCCCCCCCCCCDCLONNNMEEEEEEEEEEE",i=" \x000:XECCCCCN:lDb \x000:XECCCCCNvlDb \x000:XECCCCCN:lDb AAAAA\x00\x00\x00\x00\x00AAAAA00000AAAAA:::::AAAAAGG000AAAAA00KKKAAAAAG::::AAAAA:IIIIAAAAA000\x800AAAAA\x00\x00\x00\x00 AAAAA",h=65533,g=k.b,f=k.c,e=new A.aQ(""),d=b+1,c=a.length
if(!(b>=0&&b<c))return A.a(a,b)
s=a[b]
A:for(r=k.a;;){for(;;d=o){if(!(s>=0&&s<256))return A.a(j,s)
q=j.charCodeAt(s)&31
f=g<=32?s&61694>>>q:(s&63|f<<6)>>>0
p=g+q
if(!(p>=0&&p<144))return A.a(i,p)
g=i.charCodeAt(p)
if(g===0){p=A.v(f)
e.a+=p
if(d===a0)break A
break}else if((g&1)!==0){if(r)switch(g){case 69:case 67:p=A.v(h)
e.a+=p
break
case 65:p=A.v(h)
e.a+=p;--d
break
default:p=A.v(h)
e.a=(e.a+=p)+p
break}else{k.b=g
k.c=d-1
return""}g=0}if(d===a0)break A
o=d+1
if(!(d>=0&&d<c))return A.a(a,d)
s=a[d]}o=d+1
if(!(d>=0&&d<c))return A.a(a,d)
s=a[d]
if(s<128){for(;;){if(!(o<a0)){n=a0
break}m=o+1
if(!(o>=0&&o<c))return A.a(a,o)
s=a[o]
if(s>=128){n=m-1
o=m
break}o=m}if(n-d<20)for(l=d;l<n;++l){if(!(l<c))return A.a(a,l)
p=A.v(a[l])
e.a+=p}else{p=A.fl(a,d,n)
e.a+=p}if(n===a0)break A
d=o}else d=o}if(a1&&g>32)if(r){c=A.v(h)
e.a+=c}else{k.b=77
k.c=a0
return""}k.b=g
k.c=f
c=e.a
return c.charCodeAt(0)==0?c:c}}
A.da.prototype={
i(a){return this.L()},
$iaH:1}
A.q.prototype={
gaq(){return A.iI(this)}}
A.cy.prototype={
i(a){var s=this.a
if(s!=null)return"Assertion failed: "+A.cH(s)
return"Assertion failed"}}
A.ak.prototype={}
A.a1.prototype={
gaA(){return"Invalid argument"+(!this.a?"(s)":"")},
gaz(){return""},
i(a){var s=this,r=s.c,q=r==null?"":" ("+r+")",p=s.d,o=p==null?"":": "+A.p(p),n=s.gaA()+q+o
if(!s.a)return n
return n+s.gaz()+": "+A.cH(s.gaM())},
gaM(){return this.b}}
A.bV.prototype={
gaM(){return A.hx(this.b)},
gaA(){return"RangeError"},
gaz(){var s,r=this.e,q=this.f
if(r==null)s=q!=null?": Not less than or equal to "+A.p(q):""
else if(q==null)s=": Not greater than or equal to "+A.p(r)
else if(q>r)s=": Not in inclusive range "+A.p(r)+".."+A.p(q)
else s=q<r?": Valid value range is empty":": Only valid value is "+A.p(r)
return s}}
A.cI.prototype={
gaM(){return A.aa(this.b)},
gaA(){return"RangeError"},
gaz(){if(A.aa(this.b)<0)return": index must not be negative"
var s=this.f
if(s===0)return": no indices are valid"
return": index should be less than "+s},
gk(a){return this.f}}
A.c2.prototype={
i(a){return"Unsupported operation: "+this.a}}
A.d_.prototype={
i(a){return"UnimplementedError: "+this.a}}
A.aA.prototype={
i(a){return"Bad state: "+this.a}}
A.cE.prototype={
i(a){var s=this.a
if(s==null)return"Concurrent modification during iteration."
return"Concurrent modification during iteration: "+A.cH(s)+"."}}
A.bZ.prototype={
i(a){return"Stack Overflow"},
gaq(){return null},
$iq:1}
A.ef.prototype={
i(a){return"Exception: "+this.a}}
A.bH.prototype={
i(a){var s=this.a,r=""!==s?"FormatException: "+s:"FormatException",q=this.c
return q!=null?r+(" (at offset "+A.p(q)+")"):r}}
A.e.prototype={
gk(a){var s,r=this.gE(this)
for(s=0;r.n();)++s
return s},
X(a,b){var s,r
A.bW(b,"index")
s=this.gE(this)
for(r=b;s.n();){if(r===0)return s.gv();--r}throw A.b(A.ff(b,b-r,this,"index"))},
i(a){return A.it(this,"(",")")}}
A.u.prototype={
gp(a){return A.d.prototype.gp.call(this,0)},
i(a){return"null"}}
A.d.prototype={$id:1,
K(a,b){return this===b},
gp(a){return A.bU(this)},
i(a){return"Instance of '"+A.cR(this)+"'"},
gl(a){return A.fF(this)},
toString(){return this.i(this)}}
A.dg.prototype={
i(a){return""},
$ia6:1}
A.aQ.prototype={
gk(a){return this.a.length},
i(a){var s=this.a
return s.charCodeAt(0)==0?s:s},
$iiO:1}
A.e7.prototype={}
A.du.prototype={
aa(){var s,r,q,p,o,n,m,l,k,j,i=this,h=null
for(s=i.c,r=i.b,q=r.length;;){p=i.e
if(p+7>s.byteLength)return h
o=!1
if(p+128===q){if(!(p>=0&&p<q))return A.a(r,p)
if(r[p]===84){n=p+1
if(!(n<q))return A.a(r,n)
if(r[n]===65){o=p+2
if(!(o<q))return A.a(r,o)
o=r[o]===71}}}if(o)return h
m=A.cs(r,p)
if(m>0&&i.e+m<=q){i.e+=m
continue}l=A.eS(s,i.e)
if(l!=null){r=i.e
q=l.a
if(r+q>s.byteLength)return h
i.w=q
return l}k=i.e
j=A.k6(s,k+1)
if(j<0)return h
i.e=j
p=i.f
o=i.w
i.f=p+(o>0?B.b.t(j-k+(o/2|0),o):0)}},
C(){var s=0,r=A.G(t.a),q,p=this,o,n,m,l,k,j,i,h
var $async$C=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:if(p.r)A.n(B.G)
o=p.aa()
if(o==null){q=null
s=1
break}n=p.e
m=o.d
l=o.a
k=l-m
j=new Uint8Array(k)
i=p.c
B.c.P(j,0,k,J.fb(B.j.gI(i),i.byteOffset+(n+m)))
n=p.d
m=n>0
h=m?B.b.t(p.f*1024*1e6,n):0
p.e+=l;++p.f
q=new A.ah(j,h,h,m?B.b.t(1024e6,n):0,!0,0)
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$C,r)},
A(a){var s=0,r=A.G(t.H),q=this,p,o,n
var $async$A=A.H(function(b,c){if(b===1)return A.D(c,r)
for(;;)switch(s){case 0:if(q.r)A.n(B.G)
q.e=A.fd(q.b)
q.f=0
p=q.d
o=p>0?B.b.F(B.b.F(a*p,1e6),1024):0
for(p=0;p<o;){n=q.aa()
if(n==null)break
p=q.f
if(p>=o)break
q.e=q.e+n.a;++p
q.f=p}return A.E(null,r)}})
return A.F($async$A,r)},
gW(){var s,r,q,p,o,n,m=this,l=m.x
if(l!=null)return l
s=m.d
if(s<=0)return null
r=m.e
q=m.f
p=m.w
m.e=A.fd(m.b)
m.f=0
for(o=m.aa();o!=null;o=m.aa()){m.e=m.e+o.a;++m.f}n=m.f
m.e=r
m.f=q
m.w=p
return m.x=B.b.t(n*1024*1e6,s)},
ga1(){return!0},
u(){var s=0,r=A.G(t.H),q,p=this
var $async$u=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:q=p.r=!0
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$u,r)},
ga3(){return this.a}}
A.eu.prototype={}
A.bP.prototype={}
A.dK.prototype={
C(){var s=0,r=A.G(t.a),q,p=this,o,n,m,l,k,j
var $async$C=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:if(p.Q)A.n(B.C)
o=p.z
n=p.c
if(o>=n.length){q=null
s=1
break}m=n[o]
n=p.d
if(!(o<n.length)){q=A.a(n,o)
s=1
break}l=B.c.a4(p.b,m,m+n[o])
o=p.e
n=p.z
if(!(n<o.length)){q=A.a(o,n)
s=1
break}k=p.f
j=B.b.t(o[n]*1e6,k)
p.z=n+1
q=new A.ah(l,j,j,B.b.t(p.r*1e6,k),!0,0)
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$C,r)},
A(a){var s=0,r=A.G(t.H),q,p=this,o,n,m,l,k,j,i,h
var $async$A=A.H(function(b,c){if(b===1)return A.D(c,r)
for(;;)A:switch(s){case 0:if(p.Q)A.n(B.C)
o=a<=0?0:a
n=p.e
m=n.length
l=m-1
for(k=p.f,j=0,i=0;j<=l;){h=B.b.H(j+l,1)
if(!(h<m)){q=A.a(n,h)
s=1
break A}if(B.b.t(n[h]*1e6,k)<=o){j=h+1
i=h}else l=h-1}p.z=i
case 1:return A.E(q,r)}})
return A.F($async$A,r)},
gW(){var s=this.e,r=s.length,q=r-1
if(!(q>=0))return A.a(s,q)
return B.b.t((s[q]+this.r)*1e6,this.f)},
ga1(){return!0},
u(){var s=0,r=A.G(t.H),q,p=this
var $async$u=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:q=p.Q=!0
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$u,r)},
ga3(){return this.a}}
A.d4.prototype={}
A.ao.prototype={}
A.dL.prototype={
C(){var s=0,r=A.G(t.a),q,p=this,o,n,m,l
var $async$C=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:if(p.e)A.n(B.D)
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
break}q=new A.ah(new Uint8Array(A.L(A.cZ(l,o,n))),m.e,m.d,0,m.r,m.a)
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$C,r)},
A(a){var s=0,r=A.G(t.H),q,p=this,o,n,m,l,k,j,i,h,g,f,e
var $async$A=A.H(function(b,c){if(b===1)return A.D(c,r)
for(;;)A:switch(s){case 0:if(p.e)A.n(B.D)
o=p.a
n=B.a.cf(o,new A.dO())
for(m=p.c,l=m.length,k=o.length,j=0,i=-1,h=0;h<l;++h){g=m[h]
if(!g.r||g.e>a)continue
if(n){f=g.a
if(!(f<k)){q=A.a(o,f)
s=1
break A}f=!(o[f] instanceof A.aB)}else f=!1
if(f)continue
e=g.e
if(e>i){i=e
j=h}}p.d=j
case 1:return A.E(q,r)}})
return A.F($async$A,r)},
gW(){var s,r,q,p,o=this.c,n=o.length
if(n===0)return null
for(s=0,r=0;r<n;++r){q=o[r]
p=q.e+q.f
if(p>s)s=p}return s},
ga1(){return!0},
u(){var s=0,r=A.G(t.H),q,p=this
var $async$u=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:q=p.e=!0
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$u,r)},
ga3(){return this.a}}
A.dN.prototype={
$2(a,b){var s=t.bf
return s.a(a).b-s.a(b).b},
$S:17}
A.dM.prototype={
$1(a){return B.b.t(a*1e6,this.a.a)},
$S:9}
A.dO.prototype={
$1(a){return t.ff.a(a) instanceof A.aB},
$S:18}
A.d6.prototype={}
A.eN.prototype={
$1(a){var s,r,q,p,o,n,m
for(s=this.b,r=s.length,q=this.a,p=0,o=0;o<a;++o){n=q.a
m=n>>>3
if(m>=r)return-1
p=(p<<1|B.b.cb(s[m],7-(n&7))&1)>>>0
q.a=n+1}return p},
$S:9}
A.ee.prototype={}
A.d9.prototype={}
A.dQ.prototype={
C(){var s=0,r=A.G(t.a),q,p=this,o,n,m,l,k
var $async$C=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:if(p.r)A.n(B.F)
o=p.f
n=p.b
if(o>=n.length){q=null
s=1
break}m=n[o]
n=p.c
if(!(o<n.length)){q=A.a(n,o)
s=1
break}l=B.b.F(n[o]*1e6,48e3)
n=p.d
if(!(o<n.length)){q=A.a(n,o)
s=1
break}k=B.b.F(n[o]*1e6,48e3)
p.f=o+1
q=new A.ah(m,l,l,k,!0,0)
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$C,r)},
A(a){var s=0,r=A.G(t.H),q,p=this,o,n,m,l,k,j
var $async$A=A.H(function(b,c){if(b===1)return A.D(c,r)
for(;;)A:switch(s){case 0:if(p.r)A.n(B.F)
o=p.c
n=o.length
m=n-1
for(l=0,k=0;l<=m;){j=B.b.H(l+m,1)
if(!(j<n)){q=A.a(o,j)
s=1
break A}if(B.b.F(o[j]*1e6,48e3)<=a){l=j+1
k=j}else m=j-1}p.f=n===0?0:k
case 1:return A.E(q,r)}})
return A.F($async$A,r)},
gW(){return this.b.length===0?null:B.b.F(this.e*1e6,48e3)},
ga1(){return!0},
u(){var s=0,r=A.G(t.H),q,p=this
var $async$u=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:q=p.r=!0
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$u,r)},
ga3(){return this.a}}
A.aZ.prototype={
L(){return"_Src."+this.b}}
A.e3.prototype={
C(){var s=0,r=A.G(t.a),q,p=this,o,n,m,l,k,j,i,h,g
var $async$C=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:if(p.x)A.n(B.E)
o=p.w
n=p.c
if(o>=n){q=null
s=1
break}m=p.f
l=p.e
k=4096*(A.bt(m)*l)
j=n-o
if(j>k)j=k
j-=B.b.aS(j,A.bt(m)*l)
if(j<=0){q=null
s=1
break}i=p.bS(p.b+o,j)
h=B.b.t(j,A.bt(m)*l)
o=p.w
n=p.d
g=B.b.t(B.b.t(o,A.bt(m)*l)*1e6,n)
p.w=o+j
q=new A.ah(i,g,g,B.b.t(h*1e6,n),!0,0)
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$C,r)},
bS(a,b){var s,r,q,p,o,n,m,l,k,j,i=this.a,h=J.cu(B.j.gI(i),i.byteOffset+a,b)
switch(this.f.a){case 1:case 3:return new Uint8Array(A.L(h))
case 0:s=new Uint8Array(b*2)
r=A.a2(s,0,null)
for(i=h.length,q=r.$flags|0,p=0;p<b;++p){if(!(p<i))return A.a(h,p)
o=h[p]
q&2&&A.z(r,7)
r.setInt16(p*2,o-128<<8>>>0,!0)}return s
case 2:n=B.b.F(b,3)
s=new Uint8Array(n*4)
r=A.a2(s,0,null)
for(i=r.$flags|0,q=h.length,p=0;p<n;++p){o=p*3
if(!(o<q))return A.a(h,o)
m=h[o]
l=o+1
if(!(l<q))return A.a(h,l)
k=h[l]
o+=2
if(!(o<q))return A.a(h,o)
j=(m|k<<8|h[o]<<16)>>>0
if((j&8388608)!==0)j-=16777216
i&2&&A.z(r,12)
r.setFloat32(p*4,j/8388608,!0)}return s}},
A(a){var s=0,r=A.G(t.H),q=this,p,o,n
var $async$A=A.H(function(b,c){if(b===1)return A.D(c,r)
for(;;)switch(s){case 0:if(q.x)A.n(B.E)
p=q.f
o=q.e
n=B.b.ci(B.b.F(a*q.d,1e6)*(A.bt(p)*o),0,q.c)
q.w=n-B.b.aS(n,A.bt(p)*o)
return A.E(null,r)}})
return A.F($async$A,r)},
gW(){var s=this,r=s.d
return r>0?B.b.t(B.b.t(s.c,A.bt(s.f)*s.e)*1e6,r):null},
ga1(){return!0},
u(){var s=0,r=A.G(t.H),q,p=this
var $async$u=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:q=p.x=!0
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$u,r)},
ga3(){return this.r}}
A.eY.prototype={
$1(a){var s=0,r=A.G(t.cp),q,p=this,o,n,m,l,k,j,i
var $async$$1=A.H(function(b,c){if(b===1)return A.D(c,r)
for(;;)switch(s){case 0:if("open"===a){o=p.b
n=A.eM(o.m(0,"container"))
o=o.m(0,"bytes")
o.toString
t.p.a(o)
m=A.io(o,n==null?null:A.cG(B.aL,n,t.e))
if(m==null)throw A.b(B.ag)
p.a.a=m
o=m.ga3()
l=m.gW()
m.ga1()
q=new A.aR(o,l,!0)
s=1
break}s="read"===a?3:4
break
case 3:s=5
return A.cn(p.a.a.C(),$async$$1)
case 5:k=c
q=k==null?null:new A.aP(k)
s=1
break
case 4:j=null
o=!1
if(t.j.b(a)){l=J.cr(a)
if(l.gk(a)===2)if("seek"===l.m(a,0)){i=l.m(a,1)
o=A.co(i)
if(o){A.aa(i)
j=i}}}s=o?6:7
break
case 6:s=8
return A.cn(p.a.a.A(j),$async$$1)
case 8:q=null
s=1
break
case 7:throw A.b(A.ae("unknown op: "+A.p(a)))
case 1:return A.E(q,r)}})
return A.F($async$$1,r)},
$S:19}
A.X.prototype={
L(){return"VideoCodec."+this.b}}
A.Z.prototype={
L(){return"AudioCodec."+this.b}}
A.I.prototype={
L(){return"Container."+this.b}}
A.aj.prototype={}
A.aB.prototype={}
A.ac.prototype={}
A.aR.prototype={
gbz(){return 3329},
bo(){var s,r,q,p,o,n=A.hs(),m=this.b,l=m==null,k=l?0:1,j=n.a
j.D(k)
if(!l)n.a_(m)
j.D(this.c?1:0)
l=this.a
n.bB(l.length)
for(k=l.length,s=n.b,r=0;r<l.length;l.length===k||(0,A.b5)(l),++r){q=l[r]
if(q instanceof A.aB){j.D(0)
p=B.e.J(q.a.b)
o=n.gai()
o.$flags&2&&A.z(o,10)
o.setUint16(0,p.length,!0)
j.j(0,new Uint8Array(A.L(new Uint8Array(s.subarray(0,A.aE(0,2,8))))))
j.j(0,p)
o.setUint32(0,q.b,!0)
j.j(0,new Uint8Array(A.L(new Uint8Array(s.subarray(0,A.aE(0,4,8))))))
o.setUint32(0,q.c,!0)
j.j(0,new Uint8Array(A.L(new Uint8Array(s.subarray(0,A.aE(0,4,8))))))
o.setUint32(0,q.d,!0)
j.j(0,new Uint8Array(A.L(new Uint8Array(s.subarray(0,A.aE(0,4,8))))))
o.setUint32(0,q.e,!0)
j.j(0,new Uint8Array(A.L(new Uint8Array(s.subarray(0,A.aE(0,4,8))))))
n.a_(q.r)
n.bq(q.f)
continue}if(q instanceof A.ac){j.D(1)
p=B.e.J(q.a.b)
o=n.gai()
o.$flags&2&&A.z(o,10)
o.setUint16(0,p.length,!0)
j.j(0,new Uint8Array(A.L(new Uint8Array(s.subarray(0,A.aE(0,2,8))))))
j.j(0,p)
o.setUint32(0,q.b,!0)
j.j(0,new Uint8Array(A.L(new Uint8Array(s.subarray(0,A.aE(0,4,8))))))
o.setUint32(0,q.c,!0)
j.j(0,new Uint8Array(A.L(new Uint8Array(s.subarray(0,A.aE(0,4,8))))))
n.bq(q.d)}}return j.aP()},
$iaT:1}
A.aP.prototype={
gbz(){return 3330},
bo(){var s,r,q=A.hs(),p=this.a
q.a_(p.b)
q.a_(p.c)
q.a_(p.d)
s=p.e?1:0
r=q.a
r.D(s)
q.am(p.f)
q.bm(p.a)
return r.aP()},
$iaT:1}
A.eL.prototype={
gai(){var s,r=this,q=r.c
if(q===$){s=A.a2(r.b,0,null)
r.c!==$&&A.kQ()
r.c=s
q=s}return q},
bB(a){var s=this.gai()
s.$flags&2&&A.z(s,10)
s.setUint16(0,a,!0)
this.a.j(0,new Uint8Array(A.L(B.c.a4(this.b,0,2))))},
am(a){var s=this.gai()
s.$flags&2&&A.z(s,11)
s.setUint32(0,a,!0)
this.a.j(0,new Uint8Array(A.L(B.c.a4(this.b,0,4))))},
a_(a){var s,r=a<0,q=r?-a:a,p=B.b.F(q,4294967296)
this.am(q-p*4294967296)
this.am(p)
s=r?1:0
this.a.D(s)},
aT(a){var s=B.e.J(a)
this.bB(s.length)
this.a.j(0,s)},
bm(a){this.am(a.length)
this.a.j(0,a)},
bq(a){var s,r,q=this
if(a==null){q.a.D(0)
return}s=a.a
r=q.a
r.D(1)
if(s!=null){r.D(0)
q.aT(s.b)}else{r.D(1)
q.aT(a.b.b)}q.bm(a.c)}}
A.de.prototype={
T(a){var s=this.c,r=this.a.byteLength
if(s+a>r)throw A.b(A.a3("demux protocol: truncated message (wanted "+a+" bytes at "+s+" of "+r+")",null,null))},
O(){this.T(1)
return this.b.getUint8(this.c++)},
bA(){var s,r=this
r.T(2)
s=r.b.getUint16(r.c,!0)
r.c+=2
return s},
al(){var s,r=this
r.T(4)
s=r.b.getUint32(r.c,!0)
r.c+=4
return s},
Z(){var s=this.al(),r=this.al()*4294967296+s
return this.O()===1?-r:r},
ar(){var s,r,q=this,p=q.bA()
q.T(p)
s=q.c
s=t.L.a(A.cZ(q.a,s,s+p))
r=B.b1.J(s)
q.c+=p
return r},
bl(){var s,r,q=this,p=q.al()
q.T(p)
s=q.c
r=new Uint8Array(A.L(A.cZ(q.a,s,s+p)))
q.c+=p
return r},
bp(){var s,r,q,p=this
if(p.O()===0)return null
s=p.O()
r=p.ar()
q=p.bl()
return s===0?new A.ag(A.cG(B.P,r,t.G),null,q):new A.ag(null,A.cG(B.Q,r,t.q),q)}}
A.dJ.prototype={
i(a){return A.fF(this).i(0)+": "+this.a}}
A.w.prototype={
i(a){return"CodecInitException["+this.b+"]: "+this.a}}
A.aG.prototype={
i(a){return"CodecRuntimeException["+this.b+"]: "+this.a}}
A.ah.prototype={
i(a){var s=this,r=s.e?"KEY":"P/B"
return"EncodedPacket("+s.a.length+"B, pts="+s.b+"us, dts="+s.c+"us, "+r+", track="+s.f+")"}}
A.ag.prototype={}
A.f9.prototype={
$1(a){var s,r,q,p,o,n=A.jv(A.b_(a).data)
if(n==null)return
r=this.a
q=r.a
if(q!=null){q.cm(n)
return}s=null
try{s=A.fD(n.b,n.d)}catch(p){s=null}o=new A.di(A.h9(t.B),new A.bl(new A.j($.i,t.D),t.h))
r.a=o
A.ds(o,this.b,s,B.aa).cA(new A.f8(),t.H)},
$S:20}
A.f8.prototype={
$1(a){A.b_(v.G.self).close()},
$S:21}
A.di.prototype={
M(a){var s,r,q={},p=a.d,o=t.p.b(p),n=o?p.byteLength:0,m=new Uint8Array(12),l=A.a2(m,0,null)
l.$flags&2&&A.z(l,9)
l.setUint8(0,1)
l.setUint8(1,a.a.c)
l.setUint16(2,a.b,!0)
l.setUint32(4,a.c,!0)
l.setUint32(8,n,!0)
q.h=m
s=A.f([],t.f)
if(p!=null){p=o?p:A.fA(p,s)
q.p=p}r=A.kf(a.e,s)
A.b_(v.G.self).postMessage(q,r)},
cm(a){var s=this.a,r=s.b
if((r&4)!==0)return
s.j(0,a)},
$iiT:1}
A.eW.prototype={
$1(a){var s,r,q
for(s=this.a,r=s.length,q=0;q<r;++q)if(s[q]===a)return
B.a.j(s,a)
this.b[s.length-1]=a},
$S:22}
A.eV.prototype={
$2(a,b){this.a[A.p(a)]=A.fA(b,this.b)},
$S:1}
A.cT.prototype={
L(){return"SpawnHost."+this.b}}
A.cU.prototype={
L(){return"SpawnPayload."+this.b}}
A.dS.prototype={
by(){return A.fY(["hosted","dart","payload","js","zeroCopyTransfer",!0],t.N,t.X)},
i(a){return"SpawnCaps(hosted: dart, payload: js, zeroCopyTransfer: true)"}}
A.cm.prototype={
cr(a){var s,r,q
t.k.a(a)
this.e=a
s=this.d
if(s.length===0)return
r=A.fj(s,t.B)
B.a.N(s)
for(s=r.length,q=0;q<r.length;r.length===s||(0,A.b5)(r),++q)this.aX(r[q],a)},
c1(a){var s,r,q=this
t.B.a(a)
switch(a.a.a){case 2:s=q.b
if((s.b&4)===0)s.j(0,A.fD(a.b,a.d))
break
case 3:r=q.e
if(r==null)B.a.j(q.d,a)
else q.aX(a,r)
break
case 1:q.aF()
break
case 0:case 4:case 5:break}},
aX(a,b){var s,r,q,p,o,n,m,l,k=this,j={}
t.k.a(b)
j.a=null
try{j.a=A.fD(a.b,a.d)}catch(n){s=A.P(n)
r=A.S(n)
k.ag(a.c,s,r)
return}q=A.iZ()
try{m=q
j=A.is(new A.eI(j,b),t.X)
l=m.b
if(l==null?m!=null:l!==m)A.n(new A.ba("Local '' has already been initialized."))
m.b=j}catch(n){p=A.P(n)
o=A.S(n)
k.ag(a.c,p,o)
return}j=q
m=j.b
if(m==null?j==null:m===j)A.n(new A.ba("Local '' has not been initialized."))
m.ak(new A.eJ(k,a),new A.eK(k,a),t.P)},
ag(a,b,c){var s,r,q
t.l.a(c)
s=J.at(b)
r=A.M(s.gl(b).a,null)
s=s.i(b)
q=c.i(0)
this.a.M(new A.T(B.k,0,a,B.e.J(r+"\n"+A.fK(s,"\n"," ")+"\n"+q),null))},
c3(){return this.aF()},
aF(){var s,r=this
if(r.f)return
r.f=!0
s=r.c
if((s.a.a&30)===0)s.cj()
r.bW()
s=r.b
if((s.b&4)===0)s.u()},
bW(){var s,r,q,p,o,n,m,l=this.d
if(l.length===0)return
s=A.fj(l,t.B)
B.a.N(l)
for(l=s.length,r=this.a,q=0;q<s.length;s.length===l||(0,A.b5)(s),++q){p=s[q]
o=new A.aA("spawn: the worker closed without installing a request handler (WorkerChannel.handleRequests was never called)")
n=A.M(o.gl(0).a,null)
o=o.i(0)
m=B.B.i(0)
r.M(new A.T(B.k,0,p.c,B.e.J(n+"\n"+A.fK(o,"\n"," ")+"\n"+m),null))}},
$ifm:1}
A.eI.prototype={
$0(){return this.b.$1(this.a.a)},
$S:24}
A.eJ.prototype={
$1(a){var s,r,q,p,o,n,m,l=this
try{s=null
r=null
q=null
p=A.kv(a)
r=p.a
q=p.b
l.a.a.M(new A.T(B.V,r,l.b.c,q,s))}catch(m){o=A.P(m)
n=A.S(m)
l.a.ag(l.b.c,o,n)}},
$S:25}
A.eK.prototype={
$2(a,b){this.a.ag(this.b.c,A.ap(a),t.l.a(b))},
$S:7}
A.T.prototype={
i(a){var s=this,r=s.a.i(0),q=s.d
return"Frame("+r+", typeId: "+s.b+", correlationId: "+s.c+", payload: "+A.p(t.p.b(q)?""+q.byteLength+" bytes":J.bz(q))+")"}}
A.eQ.prototype={
$2(a,b){if(typeof a!="string")throw A.b(A.av(a,this.a,"spawn map keys must be String, got "+J.bz(a).i(0)))
A.fs(b,this.b,this.a+'["'+a+'"]')},
$S:1}
A.bT.prototype={
i(a){return"PlatformValue("+J.bz(this.a).i(0)+")"}}
A.af.prototype={
L(){return"WireKind."+this.b}}
A.d1.prototype={
i(a){var s=this
return"WireHeader(v"+s.a+", "+s.b.i(0)+", typeId: "+s.c+", correlationId: "+s.d+", payloadLength: "+s.e+")"},
K(a,b){var s=this
if(b==null)return!1
return b instanceof A.d1&&b.a===s.a&&b.b===s.b&&b.c===s.c&&b.d===s.d&&b.e===s.e},
gp(a){var s=this
return A.h1(s.a,s.b,s.c,s.d,s.e)}}
A.e4.prototype={
bw(a,b){var s,r
t.w.a(b)
if(a<1||a>65535)throw A.b(A.av(a,"typeId","must be in 1..65535 (0 is reserved)"))
s=this.a
r=s.m(0,a)
if(r!=null&&!J.ct(r,b))throw A.b(A.ae("spawn: typeId "+a+" is already registered to a different decoder"))
s.q(0,a,b)}};(function aliases(){var s=J.ax.prototype
s.bI=s.i
s=A.h.prototype
s.bJ=s.bF})();(function installTearOffs(){var s=hunkHelpers._static_1,r=hunkHelpers._static_0,q=hunkHelpers._static_2,p=hunkHelpers._instance_2u,o=hunkHelpers._instance_1u,n=hunkHelpers._instance_0u
s(A,"kj","iV",2)
s(A,"kk","iW",2)
s(A,"kl","iX",2)
r(A,"hN","kc",0)
q(A,"km","jV",6)
p(A.j.prototype,"gbN","bO",6)
s(A,"ko","jw",3)
s(A,"kt","dq",26)
s(A,"ks","iQ",27)
s(A,"kr","iH",28)
var m
o(m=A.cm.prototype,"gc0","c1",23)
n(m,"gc2","c3",0)})();(function inheritance(){var s=hunkHelpers.mixin,r=hunkHelpers.inherit,q=hunkHelpers.inheritMany
r(A.d,null)
q(A.d,[A.fh,J.cJ,A.bY,J.bA,A.d7,A.d5,A.q,A.h,A.aw,A.dR,A.e,A.aL,A.bF,A.O,A.aS,A.aY,A.dW,A.dP,A.bG,A.cd,A.R,A.dG,A.bN,A.ed,A.dh,A.a5,A.dc,A.eB,A.ez,A.c3,A.A,A.N,A.c5,A.an,A.j,A.d2,A.c_,A.ce,A.d3,A.c4,A.aC,A.d8,A.a8,A.df,A.e5,A.bj,A.dd,A.c7,A.cD,A.cF,A.es,A.eG,A.eD,A.da,A.bZ,A.ef,A.bH,A.u,A.dg,A.aQ,A.e7,A.du,A.eu,A.bP,A.dK,A.d4,A.ao,A.dL,A.d6,A.ee,A.d9,A.dQ,A.e3,A.aj,A.aR,A.aP,A.eL,A.de,A.dJ,A.ah,A.ag,A.di,A.dS,A.cm,A.T,A.bT,A.d1,A.e4])
q(J.cJ,[J.cL,J.bJ,J.bL,J.b8,J.b9,J.bK,J.b7])
q(J.bL,[J.ax,J.o,A.ay,A.bR])
q(J.ax,[J.cQ,J.c1,J.ai])
r(J.cK,A.bY)
r(J.dE,J.o)
q(J.bK,[J.bI,J.cM])
q(A.q,[A.ba,A.ak,A.cN,A.d0,A.cS,A.db,A.bM,A.cy,A.a1,A.c2,A.d_,A.aA,A.cE])
r(A.bk,A.h)
r(A.cC,A.bk)
q(A.aw,[A.cA,A.cB,A.cY,A.f2,A.f4,A.e9,A.e8,A.eO,A.eo,A.dT,A.dM,A.dO,A.eN,A.eY,A.f9,A.f8,A.eW,A.eJ])
q(A.cA,[A.f7,A.ea,A.eb,A.eA,A.eg,A.ek,A.ej,A.ei,A.eh,A.en,A.em,A.el,A.dU,A.ey,A.ex,A.ec,A.ev,A.e6,A.eU,A.eF,A.eE,A.eI])
q(A.e,[A.bD,A.br])
q(A.bD,[A.aK,A.bE,A.bO])
r(A.c0,A.aK)
r(A.bp,A.aY)
r(A.bq,A.bp)
r(A.bS,A.ak)
q(A.cY,[A.cV,A.b6])
r(A.aJ,A.R)
q(A.cB,[A.f3,A.eP,A.eX,A.ep,A.dI,A.et,A.dN,A.eV,A.eK,A.eQ])
r(A.bb,A.ay)
q(A.bR,[A.aN,A.C])
q(A.C,[A.c8,A.ca])
r(A.c9,A.c8)
r(A.bQ,A.c9)
r(A.cb,A.ca)
r(A.V,A.cb)
q(A.bQ,[A.bc,A.bd])
q(A.V,[A.be,A.bf,A.bg,A.bh,A.bi,A.aO,A.az])
r(A.ch,A.db)
r(A.bl,A.c5)
r(A.bm,A.ce)
r(A.cg,A.c_)
r(A.bn,A.cg)
r(A.bo,A.c4)
r(A.aU,A.aC)
r(A.cc,A.bj)
r(A.c6,A.cc)
r(A.cP,A.bM)
r(A.cO,A.cD)
q(A.cF,[A.dF,A.e2,A.e1])
r(A.er,A.es)
q(A.a1,[A.bV,A.cI])
q(A.da,[A.aZ,A.X,A.Z,A.I,A.cT,A.cU,A.af])
q(A.aj,[A.aB,A.ac])
q(A.dJ,[A.w,A.aG])
s(A.bk,A.aS)
s(A.c8,A.h)
s(A.c9,A.O)
s(A.ca,A.h)
s(A.cb,A.O)
s(A.bm,A.d3)})()
var v={G:typeof self!="undefined"?self:globalThis,typeUniverse:{eC:new Map(),tR:{},eT:{},tPV:{},sEA:[]},mangledGlobalNames:{c:"int",m:"double",b4:"num",a7:"String",b2:"bool",u:"Null",k:"List",d:"Object",dH:"Map",r:"JSObject"},mangledNames:{},types:["~()","~(d?,d?)","~(~())","@(@)","u(@)","u()","~(d,a6)","u(d,a6)","@()","c(c)","J<~>()","@(@,a7)","@(a7)","u(~())","~(@)","u(@,a6)","~(c,@)","c(ao,ao)","b2(aj)","J<aT?>(d?)","u(r)","u(~)","~(d)","~(T)","d?()","u(d?)","J<~>(fm)","aR(am)","aP(am)"],interceptorsByTag:null,leafTags:null,arrayRti:Symbol("$ti"),rttc:{"2;":(a,b)=>c=>c instanceof A.bq&&a.b(c.a)&&b.b(c.b)}}
A.jg(v.typeUniverse,JSON.parse('{"ai":"ax","cQ":"ax","c1":"ax","kV":"ay","o":{"k":["1"],"r":[],"e":["1"]},"cL":{"b2":[],"l":[]},"bJ":{"u":[],"l":[]},"bL":{"r":[]},"ax":{"r":[]},"cK":{"bY":[]},"dE":{"o":["1"],"k":["1"],"r":[],"e":["1"]},"bA":{"ad":["1"]},"bK":{"m":[],"b4":[]},"bI":{"m":[],"c":[],"b4":[],"l":[]},"cM":{"m":[],"b4":[],"l":[]},"b7":{"a7":[],"h2":[],"l":[]},"d7":{"fe":[]},"d5":{"fe":[]},"ba":{"q":[]},"cC":{"h":["c"],"aS":["c"],"k":["c"],"e":["c"],"h.E":"c","aS.E":"c"},"bD":{"e":["1"]},"aK":{"e":["1"]},"c0":{"aK":["1"],"e":["1"],"aK.E":"1"},"aL":{"ad":["1"]},"bE":{"e":["1"]},"bF":{"ad":["1"]},"bk":{"h":["1"],"aS":["1"],"k":["1"],"e":["1"]},"bq":{"bp":[],"aY":[]},"bS":{"ak":[],"q":[]},"cN":{"q":[]},"d0":{"q":[]},"cd":{"a6":[]},"aw":{"aI":[]},"cA":{"aI":[]},"cB":{"aI":[]},"cY":{"aI":[]},"cV":{"aI":[]},"b6":{"aI":[]},"cS":{"q":[]},"aJ":{"R":["1","2"],"fW":["1","2"],"dH":["1","2"],"R.K":"1","R.V":"2"},"bO":{"e":["1"]},"bN":{"ad":["1"]},"bp":{"aY":[]},"az":{"V":[],"am":[],"h":["c"],"C":["c"],"k":["c"],"U":["c"],"r":[],"t":[],"e":["c"],"O":["c"],"l":[],"h.E":"c"},"ay":{"r":[],"bB":[],"l":[]},"bb":{"ay":[],"r":[],"bB":[],"l":[]},"bR":{"r":[],"t":[]},"dh":{"bB":[]},"aN":{"dw":[],"r":[],"t":[],"l":[]},"C":{"U":["1"],"r":[],"t":[]},"bQ":{"h":["m"],"C":["m"],"k":["m"],"U":["m"],"r":[],"t":[],"e":["m"],"O":["m"]},"V":{"h":["c"],"C":["c"],"k":["c"],"U":["c"],"r":[],"t":[],"e":["c"],"O":["c"]},"bc":{"dz":[],"h":["m"],"C":["m"],"k":["m"],"U":["m"],"r":[],"t":[],"e":["m"],"O":["m"],"l":[],"h.E":"m"},"bd":{"dA":[],"h":["m"],"C":["m"],"k":["m"],"U":["m"],"r":[],"t":[],"e":["m"],"O":["m"],"l":[],"h.E":"m"},"be":{"V":[],"dB":[],"h":["c"],"C":["c"],"k":["c"],"U":["c"],"r":[],"t":[],"e":["c"],"O":["c"],"l":[],"h.E":"c"},"bf":{"V":[],"dC":[],"h":["c"],"C":["c"],"k":["c"],"U":["c"],"r":[],"t":[],"e":["c"],"O":["c"],"l":[],"h.E":"c"},"bg":{"V":[],"dD":[],"h":["c"],"C":["c"],"k":["c"],"U":["c"],"r":[],"t":[],"e":["c"],"O":["c"],"l":[],"h.E":"c"},"bh":{"V":[],"dY":[],"h":["c"],"C":["c"],"k":["c"],"U":["c"],"r":[],"t":[],"e":["c"],"O":["c"],"l":[],"h.E":"c"},"bi":{"V":[],"dZ":[],"h":["c"],"C":["c"],"k":["c"],"U":["c"],"r":[],"t":[],"e":["c"],"O":["c"],"l":[],"h.E":"c"},"aO":{"V":[],"e_":[],"h":["c"],"C":["c"],"k":["c"],"U":["c"],"r":[],"t":[],"e":["c"],"O":["c"],"l":[],"h.E":"c"},"db":{"q":[]},"ch":{"ak":[],"q":[]},"c3":{"dy":["1"]},"A":{"ad":["1"]},"br":{"e":["1"]},"N":{"q":[]},"c5":{"dy":["1"]},"bl":{"c5":["1"],"dy":["1"]},"j":{"J":["1"]},"ce":{"h8":["1"],"hi":["1"],"aV":["1"]},"bm":{"d3":["1"],"ce":["1"],"h8":["1"],"hi":["1"],"aV":["1"]},"bn":{"cg":["1"],"c_":["1"]},"bo":{"c4":["1"],"cW":["1"],"aV":["1"]},"c4":{"cW":["1"],"aV":["1"]},"cg":{"c_":["1"]},"aU":{"aC":["1"]},"d8":{"aC":["@"]},"c6":{"bj":["1"],"e":["1"]},"c7":{"ad":["1"]},"h":{"k":["1"],"e":["1"]},"R":{"dH":["1","2"]},"bj":{"e":["1"]},"cc":{"bj":["1"],"e":["1"]},"bM":{"q":[]},"cP":{"q":[]},"cO":{"cD":["d?","a7"]},"m":{"b4":[]},"c":{"b4":[]},"k":{"e":["1"]},"a7":{"h2":[]},"da":{"aH":[]},"cy":{"q":[]},"ak":{"q":[]},"a1":{"q":[]},"bV":{"q":[]},"cI":{"q":[]},"c2":{"q":[]},"d_":{"q":[]},"aA":{"q":[]},"cE":{"q":[]},"bZ":{"q":[]},"dg":{"a6":[]},"aQ":{"iO":[]},"aZ":{"aH":[]},"X":{"aH":[]},"Z":{"aH":[]},"I":{"aH":[]},"aB":{"aj":[]},"ac":{"aj":[]},"aR":{"aT":[]},"aP":{"aT":[]},"di":{"iT":[]},"cT":{"aH":[]},"cU":{"aH":[]},"cm":{"fm":[]},"af":{"aH":[]},"dw":{"t":[]},"dD":{"k":["c"],"t":[],"e":["c"]},"am":{"k":["c"],"t":[],"e":["c"]},"e_":{"k":["c"],"t":[],"e":["c"]},"dB":{"k":["c"],"t":[],"e":["c"]},"dY":{"k":["c"],"t":[],"e":["c"]},"dC":{"k":["c"],"t":[],"e":["c"]},"dZ":{"k":["c"],"t":[],"e":["c"]},"dz":{"k":["m"],"t":[],"e":["m"]},"dA":{"k":["m"],"t":[],"e":["m"]}}'))
A.jf(v.typeUniverse,JSON.parse('{"bD":1,"bk":1,"C":1,"aC":1,"cc":1,"cF":2}'))
var u={c:"Error handler must accept one Object or one Object and a StackTrace as arguments, and return a value of the returned future's type"}
var t=(function rtii(){var s=A.as
return{V:s("@<~>"),n:s("N"),q:s("Z"),x:s("bB"),W:s("dw"),e:s("I"),Q:s("q"),h4:s("dz"),gN:s("dA"),B:s("T"),Z:s("aI"),dQ:s("dB"),an:s("dC"),U:s("dD"),hf:s("e<@>"),hb:s("e<c>"),b4:s("o<T>"),f:s("o<d>"),s:s("o<a7>"),J:s("o<aj>"),r:s("o<am>"),fx:s("o<ao>"),gn:s("o<@>"),t:s("o<c>"),c:s("o<d?>"),T:s("bJ"),m:s("r"),g:s("ai"),aU:s("U<@>"),j:s("k<@>"),L:s("k<c>"),eE:s("dH<a7,d?>"),u:s("bb"),A:s("aN"),E:s("bc"),c2:s("bd"),at:s("be"),ha:s("bf"),cv:s("bg"),eB:s("V"),d:s("bh"),dk:s("bi"),gi:s("aO"),Y:s("az"),P:s("u"),K:s("d"),gT:s("kW"),bQ:s("+()"),l:s("a6"),N:s("a7"),ff:s("aj"),dm:s("l"),eK:s("ak"),ak:s("t"),h7:s("dY"),bv:s("dZ"),go:s("e_"),p:s("am"),bI:s("c1"),G:s("X"),bG:s("aT"),w:s("aT(am)"),h:s("bl<~>"),_:s("j<@>"),fJ:s("j<c>"),D:s("j<~>"),bf:s("ao"),fv:s("cf<d?>"),g6:s("br<d4>"),y:s("b2"),al:s("b2(d)"),i:s("m"),z:s("@"),O:s("@()"),v:s("@(d)"),C:s("@(d,a6)"),S:s("c"),a:s("ah?"),eH:s("J<u>?"),bX:s("r?"),dE:s("az?"),X:s("d?"),k:s("d?(d?)"),c8:s("a7?"),cp:s("aT?"),ev:s("aC<@>?"),F:s("an<@,@>?"),R:s("dd?"),fQ:s("b2?"),I:s("m?"),h6:s("c?"),cg:s("b4?"),b:s("~()?"),o:s("b4"),H:s("~"),M:s("~()"),d5:s("~(d)"),da:s("~(d,a6)"),as:s("~(c,@)")}})();(function constants(){var s=hunkHelpers.makeConstList
B.aB=J.cJ.prototype
B.a=J.o.prototype
B.b=J.bI.prototype
B.I=J.bK.prototype
B.m=J.b7.prototype
B.aC=J.ai.prototype
B.aD=J.bL.prototype
B.j=A.aN.prototype
B.c=A.az.prototype
B.R=J.cQ.prototype
B.r=J.c1.prototype
B.f=new A.Z(0,"aac")
B.h=new A.Z(1,"opus")
B.v=new A.Z(3,"mp3")
B.w=new A.Z(5,"pcmS16le")
B.x=new A.Z(6,"pcmF32le")
B.a2=new A.bF(A.as("bF<0&>"))
B.y=function getTagFallback(o) {
  var s = Object.prototype.toString.call(o);
  return s.substring(8, s.length - 1);
}
B.a3=function() {
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
B.a8=function(getTagFallback) {
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
B.a4=function(hooks) {
  if (typeof dartExperimentalFixupGetTag != "function") return hooks;
  hooks.getTag = dartExperimentalFixupGetTag(hooks.getTag);
}
B.a7=function(hooks) {
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
B.a6=function(hooks) {
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
B.a5=function(hooks) {
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
B.z=function(hooks) { return hooks; }

B.a9=new A.cO()
B.i=new A.dR()
B.b9=new A.cT(0,"dart")
B.ba=new A.cU(1,"js")
B.aa=new A.dS()
B.e=new A.e2()
B.d=new A.e5()
B.A=new A.d8()
B.B=new A.dg()
B.ab=new A.w("ogg","first packet is not OpusHead")
B.ac=new A.w("wav","EXTENSIBLE SubFormat is not a PCM/IEEE-float GUID")
B.ad=new A.w("ogg","not an Ogg stream")
B.ae=new A.w("mp4","no stbl samples (fragmented MP4?) \u2014 deferring to fallback")
B.af=new A.w("adts","bad ADTS sample-rate/channels")
B.ag=new A.w("container-worker","no pure-Dart parser claims this container")
B.ah=new A.w("mp4","no tracks in moov")
B.ai=new A.w("mp3","free-format MP3 (bitrate index 0) is not supported \u2014 its frame length is not derivable from the header")
B.aj=new A.w("mp3","no MPEG Layer III audio frames")
B.ak=new A.w("wav","short WAVE_FORMAT_EXTENSIBLE")
B.al=new A.w("wav","missing data chunk")
B.am=new A.w("adts","no ADTS sync")
B.an=new A.w("ogg","truncated segment table")
B.ao=new A.w("mp4","no moov box")
B.ap=new A.w("wav","missing/short fmt chunk")
B.aq=new A.w("ogg","bad page capture pattern")
B.ar=new A.w("wav","not a RIFF/WAVE file")
B.as=new A.w("ogg","truncated page payload")
B.at=new A.w("mp3","no MPEG Layer III frame sync")
B.C=new A.aG("mp3","demuxer closed")
B.D=new A.aG("mp4","demuxer closed")
B.E=new A.aG("wav","demuxer closed")
B.F=new A.aG("ogg","demuxer closed")
B.G=new A.aG("adts","demuxer closed")
B.n=new A.I(0,"mp4")
B.o=new A.I(10,"adts")
B.p=new A.I(6,"ogg")
B.q=new A.I(7,"wav")
B.H=new A.I(8,"m4a")
B.l=new A.I(9,"mp3")
B.az=new A.bH("demux protocol: unknown track kind",null,null)
B.u=new A.af(1,1,"bye")
B.aA=new A.T(B.u,0,0,null,null)
B.aE=new A.dF(null)
B.t=new A.af(0,0,"hello")
B.b7=new A.af(2,2,"message")
B.b8=new A.af(3,3,"request")
B.V=new A.af(4,4,"response")
B.k=new A.af(5,5,"error")
B.aF=s([B.t,B.u,B.b7,B.b8,B.V,B.k],A.as("o<af>"))
B.J=s([11025,12e3,8000],t.t)
B.K=s([22050,24e3,16e3],t.t)
B.L=s([44100,48e3,32e3],t.t)
B.aG=s([79,103,103,83],t.t)
B.aH=s([0,8,16,24,32,40,48,56,64,80,96,112,128,144,160,0],t.t)
B.aI=s([480,960,1920,2880,480,960,1920,2880,480,960,1920,2880,480,960,480,960,120,240,480,960,120,240,480,960,120,240,480,960,120,240,480,960],t.t)
B.M=s([79,112,117,115,72,101,97,100],t.t)
B.aJ=s(["Xing","Info"],t.s)
B.aK=s([0,0,0,0,16,0,128,0,0,170,0,56,155,113],t.t)
B.N=s([96e3,88200,64e3,48e3,44100,32e3,24e3,22050,16e3,12e3,11025,8000,7350,0,0,0],t.t)
B.O=s([],t.t)
B.S=new A.X(0,"h264")
B.T=new A.X(1,"hevc")
B.U=new A.X(2,"av1")
B.b2=new A.X(3,"vp9")
B.b3=new A.X(4,"vp8")
B.b4=new A.X(5,"mjpeg")
B.b5=new A.X(6,"prores")
B.b6=new A.X(7,"custom")
B.P=s([B.S,B.T,B.U,B.b2,B.b3,B.b4,B.b5,B.b6],A.as("o<X>"))
B.au=new A.I(1,"fmp4")
B.av=new A.I(2,"mkv")
B.aw=new A.I(3,"webm")
B.ax=new A.I(4,"mpegts")
B.ay=new A.I(5,"raw")
B.aL=s([B.n,B.au,B.av,B.aw,B.ax,B.ay,B.p,B.q,B.H,B.l,B.o],A.as("o<I>"))
B.aM=s([0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0],t.t)
B.aN=s([79,112,117,115,84,97,103,115],t.t)
B.a0=new A.Z(2,"vorbis")
B.a1=new A.Z(4,"flac")
B.Q=s([B.f,B.h,B.a0,B.v,B.a1,B.w,B.x],A.as("o<Z>"))
B.aO=s([96e3,88200,64e3,48e3,44100,32e3,24e3,22050,16e3,12e3,11025,8000,7350],t.t)
B.aP=A.a0("bB")
B.aQ=A.a0("dw")
B.aR=A.a0("dz")
B.aS=A.a0("dA")
B.aT=A.a0("dB")
B.aU=A.a0("dC")
B.aV=A.a0("dD")
B.aW=A.a0("r")
B.aX=A.a0("d")
B.aY=A.a0("dY")
B.aZ=A.a0("dZ")
B.b_=A.a0("e_")
B.b0=A.a0("am")
B.b1=new A.e1(!1)
B.W=new A.d9(0,0)
B.X=new A.aZ(0,"u8")
B.Y=new A.aZ(1,"s16")
B.Z=new A.aZ(2,"s24")
B.a_=new A.aZ(3,"f32")})();(function staticFields(){$.eq=null
$.Y=A.f([],t.f)
$.h4=null
$.fQ=null
$.fP=null
$.hO=null
$.hM=null
$.hS=null
$.f_=null
$.f5=null
$.fG=null
$.ew=A.f([],A.as("o<k<d>?>"))
$.bs=null
$.cp=null
$.cq=null
$.fv=!1
$.i=B.d})();(function lazyInitializers(){var s=hunkHelpers.lazyFinal
s($,"kT","hW",()=>A.f0("_$dart_dartClosure"))
s($,"kS","fL",()=>A.f0("_$dart_dartClosure_dartJSInterop"))
s($,"l9","by",()=>A.h0(0))
s($,"lh","ia",()=>B.d.af(B.d,A.as("J<~>()").a(new A.f7()),A.as("J<~>")))
s($,"le","i9",()=>A.f([new J.cK()],A.as("o<bY>")))
s($,"kY","hX",()=>A.al(A.dX({
toString:function(){return"$receiver$"}})))
s($,"kZ","hY",()=>A.al(A.dX({$method$:null,
toString:function(){return"$receiver$"}})))
s($,"l_","hZ",()=>A.al(A.dX(null)))
s($,"l0","i_",()=>A.al(function(){var $argumentsExpr$="$arguments$"
try{null.$method$($argumentsExpr$)}catch(r){return r.message}}()))
s($,"l3","i2",()=>A.al(A.dX(void 0)))
s($,"l4","i3",()=>A.al(function(){var $argumentsExpr$="$arguments$"
try{(void 0).$method$($argumentsExpr$)}catch(r){return r.message}}()))
s($,"l2","i1",()=>A.al(A.hb(null)))
s($,"l1","i0",()=>A.al(function(){try{null.$method$}catch(r){return r.message}}()))
s($,"l6","i5",()=>A.al(A.hb(void 0)))
s($,"l5","i4",()=>A.al(function(){try{(void 0).$method$}catch(r){return r.message}}()))
s($,"l8","fN",()=>A.iU())
s($,"kU","fa",()=>$.ia())
s($,"lc","i8",()=>A.h0(4096))
s($,"la","i6",()=>new A.eF().$0())
s($,"lb","i7",()=>new A.eE().$0())
s($,"ld","dt",()=>A.hQ(B.aX))
s($,"l7","fM",()=>new A.e4(A.fX(t.S,t.w)))})();(function nativeSupport(){!function(){var s=function(a){var m={}
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
hunkHelpers.setOrUpdateInterceptorsByTag({SharedArrayBuffer:A.ay,ArrayBuffer:A.bb,ArrayBufferView:A.bR,DataView:A.aN,Float32Array:A.bc,Float64Array:A.bd,Int16Array:A.be,Int32Array:A.bf,Int8Array:A.bg,Uint16Array:A.bh,Uint32Array:A.bi,Uint8ClampedArray:A.aO,CanvasPixelArray:A.aO,Uint8Array:A.az})
hunkHelpers.setOrUpdateLeafTags({SharedArrayBuffer:true,ArrayBuffer:true,ArrayBufferView:false,DataView:true,Float32Array:true,Float64Array:true,Int16Array:true,Int32Array:true,Int8Array:true,Uint16Array:true,Uint32Array:true,Uint8ClampedArray:true,CanvasPixelArray:true,Uint8Array:false})
A.C.$nativeSuperclassTag="ArrayBufferView"
A.c8.$nativeSuperclassTag="ArrayBufferView"
A.c9.$nativeSuperclassTag="ArrayBufferView"
A.bQ.$nativeSuperclassTag="ArrayBufferView"
A.ca.$nativeSuperclassTag="ArrayBufferView"
A.cb.$nativeSuperclassTag="ArrayBufferView"
A.V.$nativeSuperclassTag="ArrayBufferView"})()
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
var s=A.kG
if(typeof dartMainRunner==="function"){dartMainRunner(s,[])}else{s([])}})})()
//# sourceMappingURL=demux_worker.dart.js.map
