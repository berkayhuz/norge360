# syntax=docker/dockerfile:1.7

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY global.json Directory.Build.props Directory.Build.targets Directory.Packages.props ./
COPY .nuget/NuGet.Config ./.nuget/NuGet.Config
COPY packages/dotnet/src ./packages/dotnet/src
COPY services/auth/src ./services/auth/src

RUN dotnet restore services/auth/src/Norge360.Auth.API/Norge360.Auth.API.csproj --force-evaluate
RUN dotnet publish services/auth/src/Norge360.Auth.API/Norge360.Auth.API.csproj \
    -c Release \
    --no-restore \
    -o /app/publish \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

COPY --from=build /app/publish ./
RUN mkdir -p /var/lib/Norge360/auth/dataprotection \
    && chown -R $APP_UID:$APP_UID /app /var/lib/Norge360

USER $APP_UID
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "Norge360.Auth.API.dll"]
