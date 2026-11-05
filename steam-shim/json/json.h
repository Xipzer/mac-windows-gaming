



#ifndef JSON_AMALGATED_H_INCLUDED
# define JSON_AMALGATED_H_INCLUDED
#define JSON_IS_AMALGAMATION

#ifndef JSON_VERSION_H_INCLUDED
# define JSON_VERSION_H_INCLUDED

# define JSONCPP_VERSION_STRING "1.6.5"
# define JSONCPP_VERSION_MAJOR 1
# define JSONCPP_VERSION_MINOR 6
# define JSONCPP_VERSION_PATCH 5
# define JSONCPP_VERSION_QUALIFIER
# define JSONCPP_VERSION_HEXA ((JSONCPP_VERSION_MAJOR << 24) | (JSONCPP_VERSION_MINOR << 16) | (JSONCPP_VERSION_PATCH << 8))

#endif






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






#ifndef CPPTL_JSON_FEATURES_H_INCLUDED
#define CPPTL_JSON_FEATURES_H_INCLUDED

#if !defined(JSON_IS_AMALGAMATION)
#include "forwards.h"
#endif

namespace Json {

class JSON_API Features {
public:
  static Features all();

  static Features strictMode();

  Features();

  bool allowComments_;

  bool strictRoot_;

  bool allowDroppedNullPlaceholders_;

  bool allowNumericKeys_;
};

}

#endif






#ifndef CPPTL_JSON_H_INCLUDED
#define CPPTL_JSON_H_INCLUDED

#if !defined(JSON_IS_AMALGAMATION)
#include "forwards.h"
#endif
#include <string>
#include <vector>
#include <exception>

#ifndef JSON_USE_CPPTL_SMALLMAP
#include <map>
#else
#include <cpptl/smallmap.h>
#endif
#ifdef JSON_USE_CPPTL
#include <cpptl/forwards.h>
#endif

#if defined(JSONCPP_DISABLE_DLL_INTERFACE_WARNING)
#pragma warning(push)
#pragma warning(disable : 4251)
#endif

namespace Json {

class JSON_API Exception : public std::exception {
public:
  Exception(std::string const& msg);
  ~Exception() throw();
  char const* what() const throw();
protected:
  std::string msg_;
};

class JSON_API RuntimeError : public Exception {
public:
  RuntimeError(std::string const& msg);
};

class JSON_API LogicError : public Exception {
public:
  LogicError(std::string const& msg);
};

void throwRuntimeError(std::string const& msg);
void throwLogicError(std::string const& msg);

enum ValueType {
  nullValue = 0,
  intValue,
  uintValue,
  realValue,
  stringValue,
  booleanValue,
  arrayValue,
  objectValue
};

enum CommentPlacement {
  commentBefore = 0,
  commentAfterOnSameLine,
  commentAfter,
  numberOfCommentPlacement
};

class JSON_API StaticString {
public:
  explicit StaticString(const char* czstring) : c_str_(czstring) {}

  operator const char*() const { return c_str_; }

  const char* c_str() const { return c_str_; }

private:
  const char* c_str_;
};

class JSON_API Value {
  friend class ValueIteratorBase;
public:
  typedef std::vector<std::string> Members;
  typedef ValueIterator iterator;
  typedef ValueConstIterator const_iterator;
  typedef Json::UInt UInt;
  typedef Json::Int Int;
#if defined(JSON_HAS_INT64)
  typedef Json::UInt64 UInt64;
  typedef Json::Int64 Int64;
#endif
  typedef Json::LargestInt LargestInt;
  typedef Json::LargestUInt LargestUInt;
  typedef Json::ArrayIndex ArrayIndex;

  static const Value& null;
  static const Value& nullRef;
  static const LargestInt minLargestInt;
  static const LargestInt maxLargestInt;
  static const LargestUInt maxLargestUInt;

  static const Int minInt;
  static const Int maxInt;
  static const UInt maxUInt;

#if defined(JSON_HAS_INT64)
  static const Int64 minInt64;
  static const Int64 maxInt64;
  static const UInt64 maxUInt64;
#endif

private:
#ifndef JSONCPP_DOC_EXCLUDE_IMPLEMENTATION
  class CZString {
  public:
    enum DuplicationPolicy {
      noDuplication = 0,
      duplicate,
      duplicateOnCopy
    };
    CZString(ArrayIndex index);
    CZString(char const* str, unsigned length, DuplicationPolicy allocate);
    CZString(CZString const& other);
#if JSON_HAS_RVALUE_REFERENCES
    CZString(CZString&& other);
#endif
    ~CZString();
    CZString& operator=(CZString other);
    bool operator<(CZString const& other) const;
    bool operator==(CZString const& other) const;
    ArrayIndex index() const;
    char const* data() const;
    unsigned length() const;
    bool isStaticString() const;

  private:
    void swap(CZString& other);

    struct StringStorage {
      unsigned policy_: 2;
      unsigned length_: 30;
    };

    char const* cstr_;
    union {
      ArrayIndex index_;
      StringStorage storage_;
    };
  };

public:
#ifndef JSON_USE_CPPTL_SMALLMAP
  typedef std::map<CZString, Value> ObjectValues;
#else
  typedef CppTL::SmallMap<CZString, Value> ObjectValues;
#endif
#endif

public:

  Value(ValueType type = nullValue);
  Value(Int value);
  Value(UInt value);
#if defined(JSON_HAS_INT64)
  Value(Int64 value);
  Value(UInt64 value);
#endif
  Value(double value);
  Value(const char* value);
  Value(const char* begin, const char* end);

  Value(const StaticString& value);
  Value(const std::string& value);
#ifdef JSON_USE_CPPTL
  Value(const CppTL::ConstString& value);
#endif
  Value(bool value);
  Value(const Value& other);
#if JSON_HAS_RVALUE_REFERENCES
  Value(Value&& other);
#endif
  ~Value();

  Value& operator=(Value other);
  void swap(Value& other);
  void swapPayload(Value& other);

  ValueType type() const;

  bool operator<(const Value& other) const;
  bool operator<=(const Value& other) const;
  bool operator>=(const Value& other) const;
  bool operator>(const Value& other) const;
  bool operator==(const Value& other) const;
  bool operator!=(const Value& other) const;
  int compare(const Value& other) const;

  const char* asCString() const;
  std::string asString() const;
  bool getString(
      char const** begin, char const** end) const;
#ifdef JSON_USE_CPPTL
  CppTL::ConstString asConstString() const;
#endif
  Int asInt() const;
  UInt asUInt() const;
#if defined(JSON_HAS_INT64)
  Int64 asInt64() const;
  UInt64 asUInt64() const;
#endif
  LargestInt asLargestInt() const;
  LargestUInt asLargestUInt() const;
  float asFloat() const;
  double asDouble() const;
  bool asBool() const;

  bool isNull() const;
  bool isBool() const;
  bool isInt() const;
  bool isInt64() const;
  bool isUInt() const;
  bool isUInt64() const;
  bool isIntegral() const;
  bool isDouble() const;
  bool isNumeric() const;
  bool isString() const;
  bool isArray() const;
  bool isObject() const;

  bool isConvertibleTo(ValueType other) const;

  ArrayIndex size() const;

  bool empty() const;

  bool operator!() const;

  void clear();

  void resize(ArrayIndex size);

  Value& operator[](ArrayIndex index);

  Value& operator[](int index);

  const Value& operator[](ArrayIndex index) const;

  const Value& operator[](int index) const;

  Value get(ArrayIndex index, const Value& defaultValue) const;
  bool isValidIndex(ArrayIndex index) const;
  Value& append(const Value& value);

  Value& operator[](const char* key);
  const Value& operator[](const char* key) const;
  Value& operator[](const std::string& key);
  const Value& operator[](const std::string& key) const;

  Value& operator[](const StaticString& key);
#ifdef JSON_USE_CPPTL
  Value& operator[](const CppTL::ConstString& key);
  const Value& operator[](const CppTL::ConstString& key) const;
#endif
  Value get(const char* key, const Value& defaultValue) const;
  Value get(const char* begin, const char* end, const Value& defaultValue) const;
  Value get(const std::string& key, const Value& defaultValue) const;
#ifdef JSON_USE_CPPTL
  Value get(const CppTL::ConstString& key, const Value& defaultValue) const;
#endif
  Value const* find(char const* begin, char const* end) const;
  Value const* demand(char const* begin, char const* end);
  Value removeMember(const char* key);
  Value removeMember(const std::string& key);
  bool removeMember(const char* key, Value* removed);

  bool removeMember(std::string const& key, Value* removed);
  bool removeMember(const char* begin, const char* end, Value* removed);

  bool removeIndex(ArrayIndex i, Value* removed);

  bool isMember(const char* key) const;
  bool isMember(const std::string& key) const;
  bool isMember(const char* begin, const char* end) const;
#ifdef JSON_USE_CPPTL
  bool isMember(const CppTL::ConstString& key) const;
#endif

  Members getMemberNames() const;

  JSONCPP_DEPRECATED("Use setComment(std::string const&) instead.")
  void setComment(const char* comment, CommentPlacement placement);
  void setComment(const char* comment, size_t len, CommentPlacement placement);
  void setComment(const std::string& comment, CommentPlacement placement);
  bool hasComment(CommentPlacement placement) const;
  std::string getComment(CommentPlacement placement) const;

  std::string toStyledString() const;

  const_iterator begin() const;
  const_iterator end() const;

  iterator begin();
  iterator end();

  void setOffsetStart(size_t start);
  void setOffsetLimit(size_t limit);
  size_t getOffsetStart() const;
  size_t getOffsetLimit() const;

private:
  void initBasic(ValueType type, bool allocated = false);

  Value& resolveReference(const char* key);
  Value& resolveReference(const char* key, const char* end);

  struct CommentInfo {
    CommentInfo();
    ~CommentInfo();

    void setComment(const char* text, size_t len);

    char* comment_;
  };

  union ValueHolder {
    LargestInt int_;
    LargestUInt uint_;
    double real_;
    bool bool_;
    char* string_;
    ObjectValues* map_;
  } value_;
  ValueType type_ : 8;
  unsigned int allocated_ : 1;
  CommentInfo* comments_;
  Value *default_value_;

  size_t start_;
  size_t limit_;
};

class JSON_API PathArgument {
public:
  friend class Path;

  PathArgument();
  PathArgument(ArrayIndex index);
  PathArgument(const char* key);
  PathArgument(const std::string& key);

private:
  enum Kind {
    kindNone = 0,
    kindIndex,
    kindKey
  };
  std::string key_;
  ArrayIndex index_;
  Kind kind_;
};

class JSON_API Path {
public:
  Path(const std::string& path,
       const PathArgument& a1 = PathArgument(),
       const PathArgument& a2 = PathArgument(),
       const PathArgument& a3 = PathArgument(),
       const PathArgument& a4 = PathArgument(),
       const PathArgument& a5 = PathArgument());

  const Value& resolve(const Value& root) const;
  Value resolve(const Value& root, const Value& defaultValue) const;
  Value& make(Value& root) const;

private:
  typedef std::vector<const PathArgument*> InArgs;
  typedef std::vector<PathArgument> Args;

  void makePath(const std::string& path, const InArgs& in);
  void addPathInArg(const std::string& path,
                    const InArgs& in,
                    InArgs::const_iterator& itInArg,
                    PathArgument::Kind kind);
  void invalidPath(const std::string& path, int location);

  Args args_;
};

class JSON_API ValueIteratorBase {
public:
  typedef std::bidirectional_iterator_tag iterator_category;
  typedef unsigned int size_t;
  typedef int difference_type;
  typedef ValueIteratorBase SelfType;

  bool operator==(const SelfType& other) const { return isEqual(other); }

  bool operator!=(const SelfType& other) const { return !isEqual(other); }

  difference_type operator-(const SelfType& other) const {
    return other.computeDistance(*this);
  }

  Value key() const;

  UInt index() const;

  std::string name() const;

  JSONCPP_DEPRECATED("Use `key = name();` instead.")
  char const* memberName() const;
  char const* memberName(char const** end) const;

protected:
  Value& deref() const;

  void increment();

  void decrement();

  difference_type computeDistance(const SelfType& other) const;

  bool isEqual(const SelfType& other) const;

  void copy(const SelfType& other);

private:
  Value::ObjectValues::iterator current_;
  bool isNull_;

public:
  ValueIteratorBase();
  explicit ValueIteratorBase(const Value::ObjectValues::iterator& current);
};

class JSON_API ValueConstIterator : public ValueIteratorBase {
  friend class Value;

public:
  typedef const Value value_type;
  typedef const Value& reference;
  typedef const Value* pointer;
  typedef ValueConstIterator SelfType;

  ValueConstIterator();
  ValueConstIterator(ValueIterator const& other);

private:
  explicit ValueConstIterator(const Value::ObjectValues::iterator& current);
public:
  SelfType& operator=(const ValueIteratorBase& other);

  SelfType operator++(int) {
    SelfType temp(*this);
    ++*this;
    return temp;
  }

  SelfType operator--(int) {
    SelfType temp(*this);
    --*this;
    return temp;
  }

  SelfType& operator--() {
    decrement();
    return *this;
  }

  SelfType& operator++() {
    increment();
    return *this;
  }

  reference operator*() const { return deref(); }

  pointer operator->() const { return &deref(); }
};

class JSON_API ValueIterator : public ValueIteratorBase {
  friend class Value;

public:
  typedef Value value_type;
  typedef unsigned int size_t;
  typedef int difference_type;
  typedef Value& reference;
  typedef Value* pointer;
  typedef ValueIterator SelfType;

  ValueIterator();
  explicit ValueIterator(const ValueConstIterator& other);
  ValueIterator(const ValueIterator& other);

private:
  explicit ValueIterator(const Value::ObjectValues::iterator& current);
public:
  SelfType& operator=(const SelfType& other);

  SelfType operator++(int) {
    SelfType temp(*this);
    ++*this;
    return temp;
  }

  SelfType operator--(int) {
    SelfType temp(*this);
    --*this;
    return temp;
  }

  SelfType& operator--() {
    decrement();
    return *this;
  }

  SelfType& operator++() {
    increment();
    return *this;
  }

  reference operator*() const { return deref(); }

  pointer operator->() const { return &deref(); }
};

}


namespace std {
template<>
inline void swap(Json::Value& a, Json::Value& b) { a.swap(b); }
}


#if defined(JSONCPP_DISABLE_DLL_INTERFACE_WARNING)
#pragma warning(pop)
#endif

#endif






#ifndef CPPTL_JSON_READER_H_INCLUDED
#define CPPTL_JSON_READER_H_INCLUDED

#if !defined(JSON_IS_AMALGAMATION)
#include "features.h"
#include "value.h"
#endif
#include <deque>
#include <iosfwd>
#include <stack>
#include <string>
#include <istream>

#if defined(JSONCPP_DISABLE_DLL_INTERFACE_WARNING)
#pragma warning(push)
#pragma warning(disable : 4251)
#endif

namespace Json {

class JSON_API Reader {
public:
  typedef char Char;
  typedef const Char* Location;

  struct StructuredError {
    size_t offset_start;
    size_t offset_limit;
    std::string message;
  };

  Reader();

  Reader(const Features& features);

  bool
  parse(const std::string& document, Value& root, bool collectComments = true);

  bool parse(const char* beginDoc,
             const char* endDoc,
             Value& root,
             bool collectComments = true);

  bool parse(std::istream& is, Value& root, bool collectComments = true);

  JSONCPP_DEPRECATED("Use getFormattedErrorMessages() instead.")
  std::string getFormatedErrorMessages() const;

  std::string getFormattedErrorMessages() const;

  std::vector<StructuredError> getStructuredErrors() const;

  bool pushError(const Value& value, const std::string& message);

  bool pushError(const Value& value, const std::string& message, const Value& extra);

  bool good() const;

private:
  enum TokenType {
    tokenEndOfStream = 0,
    tokenObjectBegin,
    tokenObjectEnd,
    tokenArrayBegin,
    tokenArrayEnd,
    tokenString,
    tokenNumber,
    tokenTrue,
    tokenFalse,
    tokenNull,
    tokenArraySeparator,
    tokenMemberSeparator,
    tokenComment,
    tokenError
  };

  class Token {
  public:
    TokenType type_;
    Location start_;
    Location end_;
  };

  class ErrorInfo {
  public:
    Token token_;
    std::string message_;
    Location extra_;
  };

  typedef std::deque<ErrorInfo> Errors;

  bool readToken(Token& token);
  void skipSpaces();
  bool match(Location pattern, int patternLength);
  bool readComment();
  bool readCStyleComment();
  bool readCppStyleComment();
  bool readString();
  void readNumber();
  bool readValue();
  bool readObject(Token& token);
  bool readArray(Token& token);
  bool decodeNumber(Token& token);
  bool decodeNumber(Token& token, Value& decoded);
  bool decodeString(Token& token);
  bool decodeString(Token& token, std::string& decoded);
  bool decodeDouble(Token& token);
  bool decodeDouble(Token& token, Value& decoded);
  bool decodeUnicodeCodePoint(Token& token,
                              Location& current,
                              Location end,
                              unsigned int& unicode);
  bool decodeUnicodeEscapeSequence(Token& token,
                                   Location& current,
                                   Location end,
                                   unsigned int& unicode);
  bool addError(const std::string& message, Token& token, Location extra = 0);
  bool recoverFromError(TokenType skipUntilToken);
  bool addErrorAndRecover(const std::string& message,
                          Token& token,
                          TokenType skipUntilToken);
  void skipUntilSpace();
  Value& currentValue();
  Char getNextChar();
  void
  getLocationLineAndColumn(Location location, int& line, int& column) const;
  std::string getLocationLineAndColumn(Location location) const;
  std::string getLocationSnippet(Location location) const;
  void addComment(Location begin, Location end, CommentPlacement placement);
  void skipCommentTokens(Token& token);

  typedef std::stack<Value*> Nodes;
  Nodes nodes_;
  Errors errors_;
  std::string document_;
  Location begin_;
  Location end_;
  Location current_;
  Location lastValueEnd_;
  Value* lastValue_;
  std::string commentsBefore_;
  Features features_;
  bool collectComments_;
};

class JSON_API CharReader {
public:
  virtual ~CharReader() {}
  virtual bool parse(
      char const* beginDoc, char const* endDoc,
      Value* root, std::string* errs) = 0;

  class JSON_API Factory {
  public:
    virtual ~Factory() {}
    virtual CharReader* newCharReader() const = 0;
  };
};

class JSON_API CharReaderBuilder : public CharReader::Factory {
public:

  Json::Value settings_;

  CharReaderBuilder();
  ~CharReaderBuilder();

  CharReader* newCharReader() const;

  bool validate(Json::Value* invalid) const;

  Value& operator[](std::string key);

  static void setDefaults(Json::Value* settings);
  static void strictMode(Json::Value* settings);
};

bool JSON_API parseFromStream(
    CharReader::Factory const&,
    std::istream&,
    Value* root, std::string* errs);

JSON_API std::istream& operator>>(std::istream&, Value&);

}

#if defined(JSONCPP_DISABLE_DLL_INTERFACE_WARNING)
#pragma warning(pop)
#endif

#endif






#ifndef JSON_WRITER_H_INCLUDED
#define JSON_WRITER_H_INCLUDED

#if !defined(JSON_IS_AMALGAMATION)
#include "value.h"
#endif
#include <vector>
#include <string>
#include <ostream>

#if defined(JSONCPP_DISABLE_DLL_INTERFACE_WARNING)
#pragma warning(push)
#pragma warning(disable : 4251)
#endif

namespace Json {

class Value;

class JSON_API StreamWriter {
protected:
  std::ostream* sout_;
public:
  StreamWriter();
  virtual ~StreamWriter();
  virtual int write(Value const& root, std::ostream* sout) = 0;

  class JSON_API Factory {
  public:
    virtual ~Factory();
    virtual StreamWriter* newStreamWriter() const = 0;
  };
};

std::string JSON_API writeString(StreamWriter::Factory const& factory, Value const& root);


class JSON_API StreamWriterBuilder : public StreamWriter::Factory {
public:

  Json::Value settings_;

  StreamWriterBuilder();
  ~StreamWriterBuilder();

  StreamWriter* newStreamWriter() const;

  bool validate(Json::Value* invalid) const;
  Value& operator[](std::string key);

  static void setDefaults(Json::Value* settings);
};

class JSON_API Writer {
public:
  virtual ~Writer();

  virtual std::string write(const Value& root) = 0;
};

class JSON_API FastWriter : public Writer {

public:
  FastWriter();
  ~FastWriter() {}

  void enableYAMLCompatibility();

  void dropNullPlaceholders();

  void omitEndingLineFeed();

public:
  std::string write(const Value& root);

private:
  void writeValue(const Value& value);

  std::string document_;
  bool yamlCompatiblityEnabled_;
  bool dropNullPlaceholders_;
  bool omitEndingLineFeed_;
};

class JSON_API StyledWriter : public Writer {
public:
  StyledWriter();
  ~StyledWriter() {}

public:
  std::string write(const Value& root);

private:
  void writeValue(const Value& value);
  void writeArrayValue(const Value& value);
  bool isMultineArray(const Value& value);
  void pushValue(const std::string& value);
  void writeIndent();
  void writeWithIndent(const std::string& value);
  void indent();
  void unindent();
  void writeCommentBeforeValue(const Value& root);
  void writeCommentAfterValueOnSameLine(const Value& root);
  bool hasCommentForValue(const Value& value);
  static std::string normalizeEOL(const std::string& text);

  typedef std::vector<std::string> ChildValues;

  ChildValues childValues_;
  std::string document_;
  std::string indentString_;
  int rightMargin_;
  int indentSize_;
  bool addChildValues_;
};

class JSON_API StyledStreamWriter {
public:
  StyledStreamWriter(std::string indentation = "\t");
  ~StyledStreamWriter() {}

public:
  void write(std::ostream& out, const Value& root);

private:
  void writeValue(const Value& value);
  void writeArrayValue(const Value& value);
  bool isMultineArray(const Value& value);
  void pushValue(const std::string& value);
  void writeIndent();
  void writeWithIndent(const std::string& value);
  void indent();
  void unindent();
  void writeCommentBeforeValue(const Value& root);
  void writeCommentAfterValueOnSameLine(const Value& root);
  bool hasCommentForValue(const Value& value);
  static std::string normalizeEOL(const std::string& text);

  typedef std::vector<std::string> ChildValues;

  ChildValues childValues_;
  std::ostream* document_;
  std::string indentString_;
  int rightMargin_;
  std::string indentation_;
  bool addChildValues_ : 1;
  bool indented_ : 1;
};

#if defined(JSON_HAS_INT64)
std::string JSON_API valueToString(Int value);
std::string JSON_API valueToString(UInt value);
#endif
std::string JSON_API valueToString(LargestInt value);
std::string JSON_API valueToString(LargestUInt value);
std::string JSON_API valueToString(double value);
std::string JSON_API valueToString(bool value);
std::string JSON_API valueToQuotedString(const char* value);

JSON_API std::ostream& operator<<(std::ostream&, const Value& root);

}

#if defined(JSONCPP_DISABLE_DLL_INTERFACE_WARNING)
#pragma warning(pop)
#endif

#endif






#ifndef CPPTL_JSON_ASSERTIONS_H_INCLUDED
#define CPPTL_JSON_ASSERTIONS_H_INCLUDED

#include <stdlib.h>
#include <sstream>

#if !defined(JSON_IS_AMALGAMATION)
#include "config.h"
#endif

#if JSON_USE_EXCEPTION

# define JSON_ASSERT(condition)                                                \
  {if (!(condition)) {Json::throwLogicError( "assert json failed" );}}

# define JSON_FAIL_MESSAGE(message)                                            \
  {                                                                            \
    std::ostringstream oss; oss << message;                                    \
    Json::throwLogicError(oss.str());                                          \
    abort();                                                                   \
  }

#else

# define JSON_ASSERT(condition) assert(condition)

# define JSON_FAIL_MESSAGE(message)                                            \
  {                                                                            \
    std::ostringstream oss; oss << message;                                    \
    assert(false && oss.str().c_str());                                        \
    abort();                                                                   \
  }


#endif

#define JSON_ASSERT_MESSAGE(condition, message)                                \
  if (!(condition)) {                                                          \
    JSON_FAIL_MESSAGE(message);                                                \
  }

#endif





#endif
