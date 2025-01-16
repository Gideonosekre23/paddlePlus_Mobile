import React from "react";
import { Box, Button, Typography } from "@mui/material";
import { useNavigate } from "react-router-dom";
import "../styles/LandingPage.css";

const LandingPage = () => {
    const navigate = useNavigate();

    const handleRegister = () => {
      navigate("/register");
    };

    const handleLogin = () => {
      navigate("/login");
    };

    const handleMBtn = () => {
      const isOwner = true;
      navigate("/home", {state: { isOwner }})
    }

    return (
      <div className="landing-page">
        <div className="background-image"></div>
        <div className="m-btn">
          <Button onClick={handleMBtn} variant="outlined" color="primary" size="large">
            BTN
          </Button>
        </div>
        <Box className="welcome-box">
          <Typography variant="h4" gutterBottom>
            Welcome to PaddlePlus
          </Typography>
          <Typography variant="body1" gutterBottom>
            Explore, rent, and ride!
          </Typography>
          <Box mt={2}>
            <Button
              onClick={handleLogin}
              variant="contained"
              color="primary"
              size="large"
              style={{ marginRight: "10px" }}
            >
              Log In
            </Button>
            <Button onClick={handleRegister} variant="outlined" color="primary" size="large">
              Register
            </Button>
          </Box>
        </Box>
      </div>
    );
};
  
  export default LandingPage;