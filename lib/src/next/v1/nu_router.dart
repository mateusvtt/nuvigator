import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nuvigator/next.dart';
import 'package:nuvigator/src/nu_route_settings.dart';

import '../../deeplink.dart';
import '../../legacy_nurouter.dart' as legacy;
import '../../screen_route.dart';
import '../../typings.dart';

/// Extend to create your NuRoute. Contains the configuration of a Route that is
/// going to be presented in a [Nuvigator]
abstract class NuRoute<T extends NuRouter, A extends Object, R extends Object> {
  T _module;

  T get module => _module;

  NuvigatorState get nuvigator => module.nuvigator;

  bool canOpen(String deepLink) => _parser.matches(deepLink);

  ParamsParser<A> get paramsParser => null;

  Future<bool> init(BuildContext context) {
    return SynchronousFuture(true);
  }

  // TBD
  bool get prefix => false;

  ScreenType get screenType;

  String get path;

  Widget build(BuildContext context, NuRouteSettings<A> settings);

  DeepLinkParser get _parser => DeepLinkParser<A>(
        template: path,
        prefix: prefix,
        argumentParser: paramsParser,
      );

  void _install(T module) {
    _module = module;
  }

  ScreenRoute<R> _screenRoute({
    String deepLink,
    Map<String, dynamic> extraParameters,
  }) {
    final settings = _parser.toNuRouteSettings(
      deepLink: deepLink,
      arguments: extraParameters,
    );
    return ScreenRoute(
      builder: (context) => build(context, settings),
      screenType: screenType,
      nuRouteSettings: settings,
    );
  }

  ScreenRoute<R> _tryGetScreenRoute({
    String deepLink,
    Map<String, dynamic> extraParameters,
  }) {
    if (canOpen(deepLink)) {
      return _screenRoute(
        deepLink: deepLink,
        extraParameters: extraParameters,
      );
    }
    return null;
  }
}

class NuRouteBuilder<A extends Object, R extends Object>
    extends NuRoute<NuRouter, A, R> {
  NuRouteBuilder({
    @required String path,
    @required this.builder,
    this.initializer,
    this.parser,
    ScreenType screenType,
    bool prefix = false,
  })  : _path = path,
        _prefix = prefix,
        _screenType = screenType;

  final String _path;
  final NuInitFunction initializer;
  final NuRouteParametersParser<A> parser;
  final bool _prefix;
  final ScreenType _screenType;
  final NuWidgetRouteBuilder builder;

  @override
  Future<bool> init(BuildContext context) {
    if (initializer != null) {
      return initializer(context);
    }
    return super.init(context);
  }

  @override
  ParamsParser<A> get paramsParser => _parseParameters;

  A _parseParameters(Map<String, dynamic> map) =>
      parser != null ? parser(map) : null;

  @override
  Widget build(BuildContext context, NuRouteSettings<Object> settings) {
    return builder(context, this, settings);
  }

  @override
  bool get prefix => _prefix;

  @override
  String get path => _path;

  @override
  ScreenType get screenType => _screenType;
}

/// Extend to create your own NuRouter. Responsible for declaring the routes and
/// configuration of the [Nuvigator] where it will be installed.
abstract class NuRouter implements INuRouter {
  List<NuRoute> _routes;
  List<legacy.NuRouter> _legacyRouters;
  NuvigatorState _nuvigator;

  NuvigatorState get nuvigator => _nuvigator;

  @override
  void install(NuvigatorState nuvigator) {
    assert(_nuvigator == null);
    _nuvigator = nuvigator;
    for (final legacyRouter in _legacyRouters) {
      legacyRouter.install(nuvigator);
    }
  }

  @override
  void dispose() {
    _nuvigator = null;
    for (final legacyRouter in _legacyRouters) {
      legacyRouter.dispose();
    }
  }

  @override
  HandleDeepLinkFn onDeepLinkNotFound;

  /// InitialRoute that is going to be rendered
  String get initialRoute;

  /// NuRoutes to be registered in this Module
  List<NuRoute> get registerRoutes;

  /// Backwards compatible with old routers API
  List<INuRouter> get legacyRouters => [];

  @override
  T getRouter<T extends INuRouter>() {
    // ignore: avoid_as
    if (this is T) return this as T;
    for (final router in _legacyRouters) {
      final r = router.getRouter<T>();
      if (r != null) return r;
    }
    return null;
  }

  /// ScreenType to be used by the [NuRoute] registered in this Module
  /// ScreenType defined on the [NuRoute] takes precedence over the default one
  /// declared in the [NuModule]
  ScreenType get screenType => null;

  List<NuRoute> get routes => _routes;

  /// While the module is initializing this Widget is going to be displayed
  Widget loadingWidget(BuildContext context) => Container();

  /// Override to perform some processing/initialization when this module
  /// is first initialized into a [Nuvigator].
  Future<void> init(BuildContext context) async {
    return SynchronousFuture(null);
  }

  /// A common wrapper that is going to be applied to all Routes returned by
  /// this Module.
  Widget routeWrapper(BuildContext context, Widget child) {
    return child;
  }

  Future<void> _init(BuildContext context) async {
    _legacyRouters = legacyRouters.whereType<legacy.NuRouter>().toList();
    await init(context);
    _routes = registerRoutes;
    await Future.wait(_routes.map((route) async {
      assert(route._module == null);
      route._install(this);
      await route.init(context);
    }).toList());
  }

  ScreenRoute<R> _getScreenRoute<R>(String deepLink,
      {Map<String, dynamic> parameters}) {
    for (final route in routes) {
      final screenRoute = route._tryGetScreenRoute(
        deepLink: deepLink,
        extraParameters: parameters,
      );
      if (screenRoute != null) return screenRoute;
    }
    return null;
  }

  @override
  Route<R> getRoute<R>({
    String deepLink,
    Object parameters,
    @deprecated bool fromLegacyRouteName = false,
    bool isFromNative = false,
    ScreenType fallbackScreenType,
  }) {
    final route = _getScreenRoute<R>(
      deepLink,
      parameters: parameters ?? <String, dynamic>{},
    )?.fallbackScreenType(fallbackScreenType)?.toRoute();
    if (route != null) {
      if (isFromNative) {
        _addNativePopCallBack(route);
      }
      return route;
    }

    // start region: Backwards Compatible Code
    for (final legacyRouter in _legacyRouters) {
      final r = legacyRouter.getRoute<R>(
        deepLink: deepLink,
        parameters: parameters,
        isFromNative: isFromNative,
        fromLegacyRouteName: fromLegacyRouteName,
        fallbackScreenType: fallbackScreenType,
      );
      if (r != null) return r;
    }
    // end region
    return null;
  }

  void _addNativePopCallBack(Route route) {
    route.popped.then<dynamic>((dynamic _) async {
      if (nuvigator.stateTracker.stack.length == 1) {
        // We only have the backdrop route in the stack
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await SystemNavigator.pop();
      }
    });
  }
}

class NuRouterBuilder extends NuRouter {
  NuRouterBuilder({
    @required String initialRoute,
    @required List<NuRoute> routes,
    ScreenType screenType,
    WidgetBuilder loadingWidget,
    NuInitFunction init,
  })  : _initialRoute = initialRoute,
        _registerRoutes = routes,
        _screenType = screenType,
        _loadingWidget = loadingWidget,
        _initFn = init;

  final String _initialRoute;
  final List<NuRoute> _registerRoutes;
  final ScreenType _screenType;
  final WidgetBuilder _loadingWidget;
  final NuInitFunction _initFn;

  @override
  String get initialRoute => _initialRoute;

  @override
  List<NuRoute> get registerRoutes => _registerRoutes;

  @override
  ScreenType get screenType => _screenType;

  @override
  Widget loadingWidget(BuildContext context) {
    if (_loadingWidget != null) {
      return _loadingWidget(context);
    }
    return Container();
  }

  @override
  Future<void> init(BuildContext context) {
    if (_initFn != null) {
      return _initFn(context);
    }
    return super.init(context);
  }
}

class NuRouterLoader extends StatefulWidget {
  const NuRouterLoader({
    Key key,
    this.router,
    this.builder,
  }) : super(key: key);

  final NuRouter router;
  final Widget Function(NuRouter router) builder;

  @override
  _NuRouterLoaderState createState() => _NuRouterLoaderState();
}

class _NuRouterLoaderState extends State<NuRouterLoader> {
  bool loading = true;

  void _initModule() {
    widget.router._init(context).then((value) {
      setState(() {
        loading = false;
      });
    });
  }

  @override
  void didUpdateWidget(covariant NuRouterLoader oldWidget) {
    if (oldWidget.router != widget.router) {
      _initModule();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initModule();
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return widget.router.loadingWidget(context);
    }
    return widget.builder(widget.router);
  }
}
