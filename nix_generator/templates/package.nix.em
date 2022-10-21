{
@[for n in inputs]@
  @(n),
@[end for]@

  buildColconPackage,
  final,
  srcs,
}:

buildColconPackage {
  name = "@(name)";
  pkgFinal = final.@(scope_name).@(name);
  src = srcs.@(repo_name.replace("/", "_")).@(name);

@[if binary]@
  separateDebugInfo = true;

@[end if]@
  colconBuildDepends = [
@[for n in buildDepends]@
    @(n)
@[end for]@
  ];

  colconRunDepends = [
@[for n in runDepends]@
    @(n)
@[end for]@
  ];

  colconTestDepends = [
@[for n in testDepends]@
    @(n)
@[end for]@
  ];
}
