// <copyright file="PublicApiSignatureGenerator.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Reflection;

namespace Norge360.Clock.Architecture.Tests;

internal static class PublicApiSignatureGenerator
{
    internal static string[] GeneratePublicApiBaselineLines(bool strictMode = false)
    {
        var lines = new List<string>();
        var publicTypes = ArchitectureAssertions.GetProductionTypes().Where(type => type.IsPublic).OrderBy(type => type.FullName, StringComparer.Ordinal);

        foreach (var type in publicTypes)
        {
            lines.Add($"TYPE {GetTypeKind(type)} {GetFriendlyTypeName(type)}");

            foreach (var constructor in type.GetConstructors(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly).OrderBy(GetMethodSortKey, StringComparer.Ordinal))
            {
                lines.Add($"  CTOR {type.Name}({FormatParameters(constructor.GetParameters())})");
            }

            foreach (var property in type.GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly).OrderBy(property => property.Name, StringComparer.Ordinal))
            {
                lines.Add($"  PROP {GetFriendlyTypeName(property.PropertyType)} {property.Name} {{ {FormatAccessors(property)} }}");
            }

            foreach (var field in type.GetFields(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly).OrderBy(field => field.Name, StringComparer.Ordinal))
            {
                var fieldKind = field.IsLiteral ? "const" : field.IsInitOnly ? "readonly" : "field";
                lines.Add($"  FIELD {fieldKind} {GetFriendlyTypeName(field.FieldType)} {field.Name}");
            }

            foreach (var method in type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly).Where(method => !method.IsSpecialName).Where(method => !IsIgnoredMethod(method, strictMode)).OrderBy(GetMethodSortKey, StringComparer.Ordinal))
            {
                lines.Add($"  METHOD {GetFriendlyTypeName(method.ReturnType)} {method.Name}({FormatParameters(method.GetParameters())})");
            }
        }

        return lines.ToArray();
    }

    private static string GetMethodSortKey(MethodBase method) => $"{method.Name}({FormatParameters(method.GetParameters())})";

    private static string FormatParameters(IReadOnlyList<ParameterInfo> parameters) =>
        string.Join(", ", parameters.Select(parameter =>
        {
            var modifier = parameter.IsOut ? "out " : parameter.ParameterType.IsByRef ? "ref " : string.Empty;
            var parameterType = parameter.ParameterType.IsByRef ? parameter.ParameterType.GetElementType()! : parameter.ParameterType;
            return $"{modifier}{GetFriendlyTypeName(parameterType)} {parameter.Name}";
        }));

    private static string FormatAccessors(PropertyInfo property)
    {
        var accessors = new List<string>();
        if (property.GetMethod is not null && property.GetMethod.IsPublic)
        {
            accessors.Add("get;");
        }

        if (property.SetMethod is not null && property.SetMethod.IsPublic)
        {
            accessors.Add(IsInitOnlySetter(property.SetMethod) ? "init;" : "set;");
        }

        return string.Join(' ', accessors);
    }

    private static bool IsInitOnlySetter(MethodInfo setMethod) =>
        setMethod.ReturnParameter.GetRequiredCustomModifiers().Contains(typeof(System.Runtime.CompilerServices.IsExternalInit));

    private static string GetTypeKind(Type type)
    {
        if (type.IsInterface)
        {
            return "interface";
        }

        if (type.IsEnum)
        {
            return "enum";
        }

        return type.IsClass ? "class" : "type";
    }

    private static string GetFriendlyTypeName(Type type)
    {
        if (type == typeof(void))
        {
            return "void";
        }

        if (type.IsGenericParameter)
        {
            return type.Name;
        }

        if (type.IsArray)
        {
            return $"{GetFriendlyTypeName(type.GetElementType()!)}[]";
        }

        if (!type.IsGenericType)
        {
            return type.FullName ?? type.Name;
        }

        var genericTypeName = type.GetGenericTypeDefinition().FullName!;
        genericTypeName = genericTypeName[..genericTypeName.IndexOf('`')];
        var arguments = string.Join(", ", type.GetGenericArguments().Select(GetFriendlyTypeName));
        return $"{genericTypeName}<{arguments}>";
    }

    private static bool IsIgnoredMethod(MethodInfo method, bool strictMode)
    {
        if (strictMode)
        {
            return false;
        }

        if (method.Name.StartsWith("<", StringComparison.Ordinal))
        {
            return true;
        }

        return method.Name is "Equals" or "GetHashCode" or "ToString";
    }
}
