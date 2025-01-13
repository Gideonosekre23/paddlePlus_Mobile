import React, { useState } from "react";
import { Box, Button, TextField, Typography, CircularProgress } from "@mui/material";
import { loginUser } from "../utils/api";
import { useNavigate } from "react-router-dom";
import "../styles/LoginPage.css";

const LoginPage = () => {
  const navigate = useNavigate();
  const [formData, setFormData] = useState({
    username: "",
    password: "",
  });

  const [isLoading, setIsLoading] = useState(false);

  const loginSuccessDelay = 1000;

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData({ ...formData, [name]: value });
  };

  const handleSubmit = async (e) => {
    // TODO: Remove this temporary token fallback
    localStorage.clear();

    e.preventDefault();
    console.log("Login Data Submitted:", formData);

    try {
      setIsLoading(true);
      const response = await loginUser(formData); // API call to register the user
      console.log(response);
      setTimeout(() => {
        setIsLoading(false);
        navigate("/home");
      }, loginSuccessDelay);
    } catch (error) {
      // console.error("Registration failed:", error.message);
      setIsLoading(false);
    }
  };

  return (
    <div className="login-page">
      {isLoading && (
        <div className="loading-overlay">
          <CircularProgress />
          <Typography variant="body1" sx={{ mt: 2, color: "white" }}>
            Logging in... Please wait.
          </Typography>
        </div>
      )}
      
      <div className="background-image"></div>
      <Box className="form-box">
        <Typography variant="h4" gutterBottom>
          Login
        </Typography>
        <form onSubmit={handleSubmit}>
          <TextField
            fullWidth
            required
            label="Username"
            name="username"
            value={formData.username}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            required
            type="password"
            label="Password"
            name="password"
            value={formData.password}
            onChange={handleInputChange}
            margin="normal"
          />
          <Button
            variant="contained"
            color="primary"
            type="submit"
            size="large"
            fullWidth
            sx={{ mt: 3 }}
          >
            Login
          </Button>
        </form>
      </Box>
    </div>
  );
};

export default LoginPage;
