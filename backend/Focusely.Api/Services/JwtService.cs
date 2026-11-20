using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Focusely.Api.Models;
using Microsoft.IdentityModel.Tokens;

namespace Focusely.Api.Services;

public class JwtService(IConfiguration config)
{
    public string Create(User user)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(config["Jwt:Key"]!));
        var claims = new[]
        {
            new Claim("sub", user.Id.ToString()),
            new Claim("username", user.Username)
        };
        var token = new JwtSecurityToken(
            issuer: "focusely", audience: "focusely", claims: claims,
            expires: DateTime.UtcNow.AddDays(7),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
