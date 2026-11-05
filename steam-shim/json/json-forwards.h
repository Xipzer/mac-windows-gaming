



#ifndef JSON_FORWARD_AMALGATED_H_INCLUDED
# define JSON_FORWARD_AMALGATED_H_INCLUDED
#define JSON_IS_AMALGAMATION

#ifndef JSON_CONFIG_H_INCLUDED
#define JSON_CONFIG_H_INCLUDED

#ifndef JSON_USE_EXCEPTION
#define JSON_USE_EXCEPTION 1
#endif

#ifdef JSON_IN_CPPTL
#include <cpptl/config.h>
#ifndef JSON_USE_CPPTL
#define JSON_USE_CPPTL 1
#endif
#endif

#ifdef JSON_IN_CPPTL
#define JSON_API CPPTL_API
#elif defined(JSON_DLL_BUILD)
#if defined(_MSC_VER)
#define JSON_API __declspec(dllexport)
#define JSONCPP_DISABLE_DLL_INTERFACE_WARNING
#endif
#elif defined(JSON_DLL)
#if defined(_MSC_VER)
#define JSON_API __declspec(dllimport)
#define JSONCPP_DISABLE_DLL_INTERFACE_WARNING
#endif
#endif
#if !defined(JSON_API)
#define JSON_API
#endif

#if defined(_MSC_VER)
#  if _MSC_VER <= 1200
#    define JSON_USE_INT64_DOUBLE_CONVERSION 1
#    pragma warning(disable : 4786)
#  endif

#  if _MSC_VER >= 1500
#    define JSONCPP_DEPRECATED(message) __declspec(deprecated(message))
#  endif

#endif


#ifndef JSON_HAS_RVALUE_REFERENCES

#if defined(_MSC_VER) && _MSC_VER >= 1600
#define JSON_HAS_RVALUE_REFERENCES 1
#endif

#ifdef __clang__
#if __has_feature(cxx_rvalue_references)
#define JSON_HAS_RVALUE_REFERENCES 1
#endif

#elif defined __GNUC__
#if defined(__GXX_EXPERIMENTAL_CXX0X__) || (__cplusplus >= 201103L)
#define JSON_HAS_RVALUE_REFERENCES 1
#endif

#endif

#endif

#ifndef JSON_HAS_RVALUE_REFERENCES
#define JSON_HAS_RVALUE_REFERENCES 0
#endif

#ifdef __clang__
#elif defined __GNUC__
#  if (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 5))
#    define JSONCPP_DEPRECATED(message)  __attribute__ ((deprecated(message)))
#  elif (__GNUC__ > 3 || (__GNUC__ == 3 && __GNUC_MINOR__ >= 1))
#    define JSONCPP_DEPRECATED(message)  __attribute__((__deprecated__))
#  endif
#endif

#if !defined(JSONCPP_DEPRECATED)
#define JSONCPP_DEPRECATED(message)
#endif

namespace Json {
typedef int Int;
typedef unsigned int UInt;
#if defined(JSON_NO_INT64)
typedef int LargestInt;
typedef unsigned int LargestUInt;
#undef JSON_HAS_INT64
#else
#if defined(_MSC_VER)
typedef __int64 Int64;
typedef unsigned __int64 UInt64;
#else
typedef long long int Int64;
typedef unsigned long long int UInt64;
#endif
typedef Int64 LargestInt;
typedef UInt64 LargestUInt;
#define JSON_HAS_INT64
#endif
}

#endif






#ifndef JSON_FORWARDS_H_INCLUDED
#define JSON_FORWARDS_H_INCLUDED

#if !defined(JSON_IS_AMALGAMATION)
#include "config.h"
#endif

namespace Json {

class FastWriter;
class StyledWriter;

class Reader;

class Features;

typedef unsigned int ArrayIndex;
class StaticString;
class Path;
class PathArgument;
class Value;
class ValueIteratorBase;
class ValueIterator;
class ValueConstIterator;

}

#endif





#endif
