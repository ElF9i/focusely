using Focusely.Api.Data;
using Focusely.Api.Dtos;
using Focusely.Api.Models;
using Focusely.Api.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Focusely.Api.Controllers;

[ApiController, Route("api/auth")]
public class AuthController(AppDbContext db, JwtService jwt) : ControllerBase
{
    [HttpPost("register")]
    public async Task<ActionResult<AuthResponse>> Register(RegisterDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Email) || string.IsNullOrWhiteSpace(dto.Username)
            || dto.Password is null || dto.Password.Length < 8)
            return BadRequest("Email, pseudonyme requis et mot de passe d'au moins 8 caracteres.");

        var email = dto.Email.Trim().ToLowerInvariant();
        if (await db.Users.AnyAsync(u => u.Email == email))
            return Conflict("Email deja utilise.");
        if (await db.Users.AnyAsync(u => u.Username == dto.Username))
            return Conflict("Pseudonyme deja utilise.");

        var user = new User
        {
            FirstName = dto.FirstName, LastName = dto.LastName,
            Username = dto.Username, Email = email, Country = dto.Country,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(dto.Password)
        };
        db.Users.Add(user);
        await db.SaveChangesAsync();
        return Ok(new AuthResponse(jwt.Create(user), user.Id, user.Username));
    }

    [HttpPost("login")]
    public async Task<ActionResult<AuthResponse>> Login(LoginDto dto)
    {
        var email = dto.Email.Trim().ToLowerInvariant();
        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == email);
        if (user is null || !BCrypt.Net.BCrypt.Verify(dto.Password, user.PasswordHash))
            return Unauthorized("Identifiants invalides.");
        return Ok(new AuthResponse(jwt.Create(user), user.Id, user.Username));
    }
}
