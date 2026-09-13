# ---------- Stage 1: Build ----------
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS builder

WORKDIR /src

COPY crud-asp.net-core.csproj .
RUN dotnet restore crud-asp.net-core.csproj

COPY . .
RUN dotnet publish crud-asp.net-core.csproj -c Release -o /app/publish --no-restore


# ---------- Stage 2: Runtime ----------
FROM mcr.microsoft.com/dotnet/aspnet:9.0

WORKDIR /app

COPY --from=builder /app/publish .

EXPOSE 80

ENTRYPOINT ["dotnet", "crud-asp.net-core.dll"]