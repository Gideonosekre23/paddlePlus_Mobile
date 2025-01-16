import React, { useState } from "react";
import { Box, Button, TextField, Typography, CircularProgress, FormControlLabel, Checkbox } from "@mui/material";
import { loginUser } from "../utils/api";
import { useNavigate } from "react-router-dom";
import saveToLocalStorage from "../utils/utils";
import "../styles/LoginPage.css";

const LoginPage = () => {
  const navigate = useNavigate();
  const [formData, setFormData] = useState({
    username: "",
    password: "",
  });

  const [isOwner, setIsOwner] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  const loginSuccessDelay = 1000;

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData({ ...formData, [name]: value });
  };

  const handleCheckboxChange = (e) => {
    setIsOwner(e.target.checked);
  };

  const handleSubmit = async (e) => {
    // TODO: Remove this temporary token fallback
    localStorage.clear();

    e.preventDefault();
    console.log("Login Data Submitted:", formData);

    try {
      setIsLoading(true);
      const response = await loginUser(formData, isOwner);
      console.log(response.user);
      saveToLocalStorage(response.user);
      setTimeout(() => {
        setIsLoading(false);
        navigate("/home", {state: { isOwner }});
      }, loginSuccessDelay);
    } catch (error) {
      console.error("Registration failed:", error.message);
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
          <FormControlLabel
            control={
              <Checkbox
                checked={isOwner}
                onChange={handleCheckboxChange}
                color="primary"
              />
            }
            label="Log in as an owner"
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
