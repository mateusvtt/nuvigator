import 'package:path_to_regexp/path_to_regexp.dart';
import 'package:recase/recase.dart';

class DeepLinkParser {
  DeepLinkParser(this.template, {this.prefix = false});

  final String template;
  final bool prefix;

  bool matches(String deepLink) {
    final regExp = pathToRegExp(template, prefix: prefix);
    return regExp.hasMatch(deepLink);
  }

  Map<String, String> getParams(String deepLink) {
    return {...getQueryParams(deepLink), ...getPathParams(deepLink)};
  }

  Map<String, String> getQueryParams(String deepLink) {
    final parametersMap = Uri.parse(deepLink).queryParameters;
    return parametersMap.map((k, v) {
      return MapEntry(ReCase(k).camelCase, v);
    });
  }

  Map<String, String> getPathParams(String deepLink) {
    final parameters = <String>[];
    final regExp = pathToRegExp(template, parameters: parameters);
    final match = regExp.matchAsPrefix(deepLink);
    final parametersMap = extract(parameters, match);
    return parametersMap.map((k, v) {
      return MapEntry(ReCase(k).camelCase, v);
    });
  }
}
